-- Phase 8 gap closure: escrow refunds.
--
-- `escrow_status` has always declared 'REFUNDED', and two guards require it
-- (023 enforce_job_financial_state, 032 its successor): a job may only reach
-- CANCELLED while escrow is UNFUNDED or REFUNDED. Nothing ever wrote
-- 'REFUNDED'. The consequences were that a funded job could never be
-- cancelled, and that a client dispute (which moves HELD -> FROZEN) stranded
-- the money permanently: no transition leaves FROZEN, so the client stayed
-- charged and the worker stayed unpaid with no operator remedy.
--
-- This migration adds the missing terminal edge. It is forward-only; earlier
-- migrations are already applied and checksum-pinned by scripts/migrate.ts.

-- 1. A refund is its own audited administrative action. Reusing JOB_CANCELLED
--    would silently widen that action's permitted transitions.
ALTER TABLE public.admin_audit_log
  DROP CONSTRAINT admin_audit_log_action_check;

ALTER TABLE public.admin_audit_log
  ADD CONSTRAINT admin_audit_log_action_check CHECK (
    action IN (
      'JOB_STATUS_OVERRIDE',
      'JOB_REASSIGNED',
      'JOB_CANCELLED',
      'JOB_REFUNDED',
      'USER_SUSPENDED',
      'WORKER_VERIFICATION_UPDATED'
    )
  );

-- 2. Teach the lifecycle override gate about the new action.
CREATE OR REPLACE FUNCTION job_override_is_authorized(
  p_job_id UUID,
  p_old_status job_status,
  p_new_status job_status,
  p_old_worker_id UUID,
  p_new_worker_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.admin_audit_log AS audit
    WHERE audit.entity_type = 'JOB'
      AND audit.entity_id = p_job_id
      AND audit.override_txid = txid_current()
      AND audit.action IN ('JOB_STATUS_OVERRIDE', 'JOB_REASSIGNED', 'JOB_CANCELLED', 'JOB_REFUNDED')
      AND audit.before_state @> jsonb_build_object(
        'status', p_old_status::text,
        'worker_id', p_old_worker_id
      )
      AND audit.after_state @> jsonb_build_object(
        'status', p_new_status::text,
        'worker_id', p_new_worker_id
      )
  );
$$;

-- 3. Validate the refund edge itself. Preserves every rule from migration 035
--    and adds JOB_REFUNDED: any non-terminal job, escrow HELD or FROZEN, to
--    CANCELLED with escrow REFUNDED.
CREATE OR REPLACE FUNCTION enforce_admin_audit_job_transition()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_from_status TEXT;
  v_to_status TEXT;
  v_from_escrow TEXT;
  v_to_escrow TEXT;
  v_suspension_cause BOOLEAN;
BEGIN
  IF NEW.entity_type <> 'JOB' THEN
    RETURN NEW;
  END IF;

  v_from_status := NEW.before_state ->> 'status';
  v_to_status := NEW.after_state ->> 'status';
  v_from_escrow := NEW.before_state ->> 'escrow_status';
  v_to_escrow := NEW.after_state ->> 'escrow_status';
  v_suspension_cause := (NEW.metadata ->> 'cause') IN ('CLIENT_SUSPENDED', 'WORKER_SUSPENDED');
  IF v_from_status IS NULL OR v_to_status IS NULL THEN
    RAISE EXCEPTION 'Job audit entries require before and after status' USING ERRCODE = '23514';
  END IF;

  IF NEW.action = 'JOB_REASSIGNED' THEN
    IF v_from_status <> 'ASSIGNED'
      OR v_to_status <> 'ASSIGNED'
      OR (NEW.before_state ->> 'worker_id') IS NOT DISTINCT FROM (NEW.after_state ->> 'worker_id') THEN
      RAISE EXCEPTION 'Administrative reassignment is allowed only while ASSIGNED' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.action = 'JOB_STATUS_OVERRIDE' THEN
    IF NOT (
      (v_from_status = 'ASSIGNED' AND v_to_status IN ('EN_ROUTE', 'DISPUTED', 'CANCELLED')) OR
      (v_from_status = 'EN_ROUTE' AND v_to_status IN ('AT_LOCATION', 'DISPUTED', 'CANCELLED')) OR
      (v_from_status = 'AT_LOCATION' AND v_to_status IN ('IN_PROGRESS', 'DISPUTED', 'CANCELLED')) OR
      (v_from_status = 'IN_PROGRESS' AND v_to_status IN ('SUBMITTED', 'DISPUTED', 'CANCELLED')) OR
      (v_from_status = 'SUBMITTED' AND v_to_status IN ('APPROVED', 'DISPUTED')) OR
      (v_from_status = 'APPROVED' AND v_to_status IN ('COMPLETED', 'DISPUTED')) OR
      (v_from_status = 'DISPUTED' AND v_to_status = 'APPROVED') OR
      (v_suspension_cause AND v_from_status = 'POSTED' AND v_to_status = 'DISPUTED') OR
      (v_suspension_cause AND v_from_status = 'FUNDING' AND v_to_status = 'FUNDING'
        AND v_from_escrow = 'PENDING' AND v_to_escrow = 'FROZEN') OR
      (v_suspension_cause AND v_from_status = 'DISPUTED' AND v_to_status = 'DISPUTED'
        AND v_from_escrow = 'HELD' AND v_to_escrow = 'FROZEN')
    ) THEN
      RAISE EXCEPTION 'Administrative status transition is not canonical' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.action = 'JOB_REFUNDED' THEN
    IF NOT (
      v_to_status = 'CANCELLED'
      AND v_from_status NOT IN ('COMPLETED', 'CANCELLED')
      AND v_from_escrow IN ('HELD', 'FROZEN')
      AND v_to_escrow = 'REFUNDED'
    ) THEN
      RAISE EXCEPTION 'Administrative refund is not canonical' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.action = 'JOB_CANCELLED' THEN
    IF NOT (
      (v_from_status = 'POSTED' AND v_to_status = 'CANCELLED') OR
      (v_from_status = 'ASSIGNED' AND v_to_status = 'CANCELLED') OR
      (v_from_status = 'EN_ROUTE' AND v_to_status = 'CANCELLED') OR
      (v_from_status = 'AT_LOCATION' AND v_to_status = 'CANCELLED') OR
      (v_from_status = 'IN_PROGRESS' AND v_to_status = 'CANCELLED')
    ) THEN
      RAISE EXCEPTION 'Administrative cancellation is not canonical' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- 4. Post a real running balance on every ledger posting.
--
-- post_ledger_transaction has always written a literal 0 into
-- balance_after_cents, while repository.ts serves that column to clients as the
-- wallet running balance. The column is immutable once written (023/024), so
-- the value has to be correct at insert time. Locking the account row
-- serializes concurrent posters against the same account, which is what makes
-- the running sum well-defined.
CREATE OR REPLACE FUNCTION post_ledger_transaction(
  p_job_id UUID,
  p_transaction_status transaction_status,
  p_currency CHAR(3),
  p_idempotency_key VARCHAR,
  p_idempotency_fingerprint CHAR(64),
  p_description TEXT,
  p_metadata JSONB,
  p_entries JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_transaction_id UUID;
  v_existing_fingerprint CHAR(64);
  v_entry JSONB;
  v_entry_index INTEGER := 0;
  v_owner_user_id UUID;
  v_account_kind ledger_account_kind;
  v_account_id UUID;
  v_amount_cents BIGINT;
  v_transaction_type transaction_type;
  v_balance_after_cents BIGINT;
BEGIN
  IF p_transaction_status NOT IN ('PENDING', 'COMPLETED')
    OR p_currency !~ '^[A-Z]{3}$'
    OR p_idempotency_key IS NULL
    OR length(btrim(p_idempotency_key)) < 8
    OR length(p_idempotency_key) > 200
    OR p_idempotency_fingerprint !~ '^[0-9a-f]{64}$'
    OR length(btrim(COALESCE(p_description, ''))) = 0
    OR jsonb_typeof(p_entries) <> 'array'
    OR jsonb_array_length(p_entries) < 2 THEN
    RAISE EXCEPTION 'Invalid ledger transaction request' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_idempotency_key, 109));
  SELECT id, idempotency_fingerprint
  INTO v_transaction_id, v_existing_fingerprint
  FROM public.ledger_transactions
  WHERE idempotency_key = p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing_fingerprint <> p_idempotency_fingerprint THEN
      RAISE EXCEPTION 'Ledger idempotency key was reused with different input' USING ERRCODE = '23505';
    END IF;
    RETURN v_transaction_id;
  END IF;

  INSERT INTO public.ledger_transactions (
    job_id, transaction_status, currency, idempotency_key,
    idempotency_fingerprint, description, metadata, processed_at
  ) VALUES (
    p_job_id, p_transaction_status, p_currency, p_idempotency_key,
    p_idempotency_fingerprint, btrim(p_description), COALESCE(p_metadata, '{}'::jsonb),
    CASE WHEN p_transaction_status = 'COMPLETED' THEN NOW() ELSE NULL END
  ) RETURNING id INTO v_transaction_id;

  FOR v_entry IN SELECT value FROM jsonb_array_elements(p_entries)
  LOOP
    v_entry_index := v_entry_index + 1;
    BEGIN
      v_owner_user_id := NULLIF(v_entry ->> 'owner_user_id', '')::uuid;
      v_account_kind := (v_entry ->> 'account_kind')::ledger_account_kind;
      v_amount_cents := (v_entry ->> 'amount_cents')::bigint;
      v_transaction_type := (v_entry ->> 'transaction_type')::transaction_type;
    EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value THEN
      RAISE EXCEPTION 'Ledger entry is malformed' USING ERRCODE = '22023';
    END;
    IF v_amount_cents = 0 THEN
      RAISE EXCEPTION 'Ledger entries cannot be zero' USING ERRCODE = '22023';
    END IF;
    v_account_id := public.get_or_create_ledger_account(v_owner_user_id, v_account_kind, p_currency);

    -- Serialize posters against this account so the running sum below cannot
    -- read a balance another transaction is concurrently adding to.
    PERFORM 1 FROM public.ledger_accounts WHERE id = v_account_id FOR UPDATE;
    SELECT COALESCE(SUM(posting.amount_cents), 0) + v_amount_cents
    INTO v_balance_after_cents
    FROM public.wallet_ledger AS posting
    WHERE posting.ledger_account_id = v_account_id;

    INSERT INTO public.wallet_ledger (
      user_id, job_id, transaction_type, transaction_status, amount_cents,
      balance_after_cents, currency, reference_id, reference_type, description,
      metadata, idempotency_key, processed_at, ledger_transaction_id, ledger_account_id
    ) VALUES (
      v_owner_user_id, p_job_id, v_transaction_type, p_transaction_status, v_amount_cents,
      v_balance_after_cents, p_currency, v_transaction_id::text, 'LEDGER_TRANSACTION', btrim(p_description),
      COALESCE(v_entry -> 'metadata', '{}'::jsonb) || jsonb_build_object('ledger_transaction_id', v_transaction_id),
      p_idempotency_key || ':' || v_entry_index::text,
      CASE WHEN p_transaction_status = 'COMPLETED' THEN NOW() ELSE NULL END,
      v_transaction_id, v_account_id
    );
  END LOOP;
  RETURN v_transaction_id;
END;
$$;

-- 5. The refund itself.
--
-- Escrow HELD or FROZEN -> REFUNDED, reversing the original funding hold as a
-- balanced double-entry pair, and driving the job to CANCELLED in the same
-- UPDATE. Both columns must move together: enforce_job_financial_state is a
-- BEFORE trigger that rejects CANCELLED unless escrow is already UNFUNDED or
-- REFUNDED, and rejects an active status whose escrow is not HELD.
--
-- Idempotency follows begin_escrow_funding: an advisory lock on the key, then a
-- fingerprint check against the existing ledger transaction. A replay with the
-- same key returns the original result; the same key with different input is a
-- conflict.
CREATE OR REPLACE FUNCTION refund_client_job(
  p_actor_user_id UUID,
  p_job_id UUID,
  p_reason TEXT,
  p_idempotency_key VARCHAR,
  p_idempotency_fingerprint CHAR(64)
)
RETURNS TABLE (
  audit_id BIGINT,
  job_id UUID,
  status job_status,
  escrow_status escrow_status,
  refund_ledger_transaction_id UUID,
  refunded_amount_cents BIGINT,
  currency CHAR(3)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
#variable_conflict use_column
DECLARE
  v_reason TEXT := btrim(p_reason);
  v_initial_worker_id UUID;
  v_status job_status;
  v_escrow_status escrow_status;
  v_client_id UUID;
  v_worker_id UUID;
  v_budget_cents BIGINT;
  v_currency CHAR(3);
  v_refund_transaction_id UUID;
  v_existing_fingerprint CHAR(64);
  v_audit_id BIGINT;
  v_before JSONB;
  v_after JSONB;
BEGIN
  PERFORM public.assert_active_admin(p_actor_user_id);
  IF length(v_reason) < 3 THEN
    RAISE EXCEPTION 'An administrative reason is required' USING ERRCODE = '22023';
  END IF;
  IF p_idempotency_key IS NULL
    OR length(btrim(p_idempotency_key)) < 8
    OR length(p_idempotency_key) > 180
    OR p_idempotency_fingerprint !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'Invalid refund request' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_job_id::text || ':' || p_idempotency_key, 131));

  -- Replay: the refund ledger transaction already exists for this key.
  SELECT txn.id, txn.idempotency_fingerprint
  INTO v_refund_transaction_id, v_existing_fingerprint
  FROM public.ledger_transactions AS txn
  WHERE txn.idempotency_key = p_idempotency_key || ':refund'
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing_fingerprint <> p_idempotency_fingerprint THEN
      RAISE EXCEPTION 'Refund idempotency key was reused with different input' USING ERRCODE = '23505';
    END IF;
    SELECT j.id, j.status, j.escrow_status, j.budget_cents, j.currency
    INTO job_id, status, escrow_status, v_budget_cents, v_currency
    FROM public.jobs AS j WHERE j.id = p_job_id;
    SELECT audit.id INTO v_audit_id
    FROM public.admin_audit_log AS audit
    WHERE audit.entity_type = 'JOB'
      AND audit.entity_id = p_job_id
      AND audit.action = 'JOB_REFUNDED'
    ORDER BY audit.id DESC
    LIMIT 1;
    RETURN QUERY SELECT v_audit_id, p_job_id, status, escrow_status,
      v_refund_transaction_id, v_budget_cents, v_currency;
    RETURN;
  END IF;

  -- Lock ordering mirrors admin_override_job: worker profile before the job row.
  SELECT j.worker_id INTO v_initial_worker_id FROM public.jobs AS j WHERE j.id = p_job_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Job not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_initial_worker_id IS NOT NULL THEN
    PERFORM 1 FROM public.worker_profiles AS wp WHERE wp.user_id = v_initial_worker_id FOR UPDATE;
  END IF;

  SELECT j.status, j.escrow_status, j.client_id, j.worker_id, j.budget_cents, j.currency
  INTO v_status, v_escrow_status, v_client_id, v_worker_id, v_budget_cents, v_currency
  FROM public.jobs AS j WHERE j.id = p_job_id FOR UPDATE;
  IF v_worker_id IS DISTINCT FROM v_initial_worker_id THEN
    RAISE EXCEPTION 'Job assignment changed; retry the refund' USING ERRCODE = '40001';
  END IF;

  IF v_escrow_status NOT IN ('HELD', 'FROZEN') THEN
    RAISE EXCEPTION 'Only a funded escrow (HELD or FROZEN) can be refunded' USING ERRCODE = '55000';
  END IF;
  IF v_status IN ('COMPLETED', 'CANCELLED') THEN
    RAISE EXCEPTION 'Terminal jobs cannot be refunded' USING ERRCODE = '55000';
  END IF;
  IF v_budget_cents <= 0 THEN
    RAISE EXCEPTION 'Refund amount must be positive' USING ERRCODE = '23514';
  END IF;

  -- Reverse the original hold: gateway clearing gave escrow the money, so the
  -- money goes back the way it came.
  v_refund_transaction_id := public.post_ledger_transaction(
    p_job_id, 'COMPLETED', v_currency, p_idempotency_key || ':refund', p_idempotency_fingerprint,
    'Escrow refunded to client', jsonb_build_object('reason', v_reason, 'actor_user_id', p_actor_user_id),
    jsonb_build_array(
      jsonb_build_object('account_kind', 'CLIENT_ESCROW', 'owner_user_id', v_client_id, 'amount_cents', v_budget_cents, 'transaction_type', 'REFUND'),
      jsonb_build_object('account_kind', 'PLATFORM_GATEWAY_CLEARING', 'amount_cents', -v_budget_cents, 'transaction_type', 'REFUND')
    )
  );

  v_before := jsonb_build_object(
    'status', v_status::text,
    'worker_id', v_worker_id,
    'escrow_status', v_escrow_status::text
  );
  v_after := jsonb_build_object(
    'status', 'CANCELLED',
    'worker_id', NULL,
    'escrow_status', 'REFUNDED'
  );
  INSERT INTO public.admin_audit_log (
    actor_user_id, action, entity_type, entity_id, reason,
    before_state, after_state, metadata, override_txid
  ) VALUES (
    p_actor_user_id, 'JOB_REFUNDED', 'JOB', p_job_id, v_reason,
    v_before, v_after,
    jsonb_build_object(
      'client_id', v_client_id,
      'refund_ledger_transaction_id', v_refund_transaction_id,
      'refunded_amount_cents', v_budget_cents
    ),
    txid_current()
  ) RETURNING id INTO v_audit_id;

  UPDATE public.jobs AS j
  SET status = 'CANCELLED',
      escrow_status = 'REFUNDED',
      worker_id = NULL,
      cancelled_at = NOW(),
      cancellation_reason = v_reason,
      updated_at = NOW()
  WHERE j.id = p_job_id;

  -- Release the worker back to the pool once they have no other live work.
  IF v_worker_id IS NOT NULL THEN
    UPDATE public.worker_profiles AS wp
    SET is_available = TRUE, updated_at = NOW()
    WHERE wp.user_id = v_worker_id
      AND wp.verification_status = 'VERIFIED'
      AND EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_worker_id AND u.is_active = TRUE)
      AND NOT EXISTS (
        SELECT 1 FROM public.jobs AS active_job
        WHERE active_job.worker_id = v_worker_id
          AND active_job.status IN ('ASSIGNED', 'EN_ROUTE', 'AT_LOCATION', 'IN_PROGRESS', 'SUBMITTED', 'APPROVED', 'DISPUTED')
      );
  END IF;

  RETURN QUERY SELECT v_audit_id, p_job_id, 'CANCELLED'::job_status, 'REFUNDED'::escrow_status,
    v_refund_transaction_id, v_budget_cents, v_currency;
END;
$$;

REVOKE EXECUTE ON FUNCTION refund_client_job(UUID, UUID, TEXT, VARCHAR, CHAR(64)) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION post_ledger_transaction(UUID, transaction_status, CHAR(3), VARCHAR, CHAR(64), TEXT, JSONB, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION job_override_is_authorized(UUID, job_status, job_status, UUID, UUID) FROM PUBLIC;

-- Refunds are issued over the admin connection (adminPool / DATABASE_ADMIN_URL),
-- so the grant matches admin_override_job. scripts/provision-app-role.sql
-- carries the same line for freshly provisioned databases.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'networkpeer_admin_api') THEN
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.refund_client_job(UUID, UUID, TEXT, VARCHAR, CHAR(64)) TO networkpeer_admin_api';
  END IF;
END;
$$;
