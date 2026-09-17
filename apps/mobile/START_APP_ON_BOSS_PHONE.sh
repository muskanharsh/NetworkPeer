#!/bin/bash
set -e

echo "========================================================"
echo "   NetworkPeer — Mobile App Remote Demo Launcher       "
echo "========================================================"
echo ""
echo "This script starts the mobile app with a global cloud tunnel."
echo "Your boss does NOT need USB cables or developer settings!"
echo ""
echo "Instructions for Boss's Phone:"
echo " 1. Install 'Expo Go' from Google Play Store or iOS App Store."
echo " 2. Open Camera (or Expo Go app) and SCAN THE QR CODE below."
echo " 3. The NetworkPeer app will launch immediately on their phone!"
echo ""
echo "Connecting to AWS Staging API:"
echo " http://networkpeer-staging-api-alb-969746120.eu-north-1.elb.amazonaws.com"
echo ""
echo "For Demo Login on Phone:"
echo " - Enter any 10-digit phone number (+91)"
echo " - Enter the verification code emailed to you"
echo "========================================================"
echo ""

cd "$(dirname "$0")"

echo "Select connection mode:"
echo " 1) Same Wi-Fi / LAN (Fastest, instant QR code - Recommended for Office/Hotspot)"
echo " 2) Cloud Tunnel (Works anywhere, cellular data / different networks)"
echo ""
read -t 10 -p "Enter choice [1 or 2] (default is 1 in 10s): " CHOICE || CHOICE="1"
CHOICE=${CHOICE:-1}

if [ "$CHOICE" = "2" ]; then
  echo ""
  echo "🚀 Launching Expo Go with Cloud Tunnel..."
  npx expo start --go --tunnel -c
else
  echo ""
  echo "🚀 Launching Expo Go on Local Network (LAN)..."
  npx expo start --go --lan -c
fi
