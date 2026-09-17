import java.util.Properties
import java.net.URI

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val defaultBackendApiUrl = "http://networkpeer-staging-api-alb-969746120.eu-north-1.elb.amazonaws.com/api/v1/"
val defaultBackendRealtimeUrl = "http://networkpeer-staging-api-alb-969746120.eu-north-1.elb.amazonaws.com"
val defaultBackendRealtimeOrigin = "https://networkpeer-platform.vercel.app"
val unconfiguredApiUrl = defaultBackendApiUrl
val developmentProperties = loadLocalProperties("networkpeer.development.local.properties")
val productionProperties = loadLocalProperties("networkpeer.production.local.properties")
val developmentGoogleServices = project.file("src/development/google-services.json")
val productionGoogleServices = project.file("src/production/google-services.json")
val allowedGoogleServicesFiles = setOf(
    developmentGoogleServices.canonicalFile,
    productionGoogleServices.canonicalFile,
)
val unexpectedGoogleServicesFiles = fileTree("src") {
    include("**/google-services.json")
}.files.filter { it.canonicalFile !in allowedGoogleServicesFiles }

check(!project.file("google-services.json").isFile && unexpectedGoogleServicesFiles.isEmpty()) {
    "Firebase configuration must be flavor-specific: use src/development/google-services.json " +
        "or src/production/google-services.json. A shared or build-type Firebase config can mix accounts."
}

fun String.asBuildConfigString(): String = "\"${replace("\\", "\\\\").replace("\"", "\\\"")}\""

fun configuredApiUrl(value: String): Boolean {
    val trimmed = value.trim()
    val uri = runCatching { URI(trimmed) }.getOrNull() ?: return false
    val scheme = uri.scheme?.lowercase() ?: return false
    val host = uri.host?.lowercase() ?: return false
    val hostStr = host as String
    val isPlaceholderHost = hostStr == "example" || hostStr.endsWith(".example") ||
        hostStr == "example.com" || hostStr.endsWith(".example.com") ||
        hostStr == "invalid" || hostStr.endsWith(".invalid")
    return (scheme == "https" || scheme == "http") && !isPlaceholderHost
}

fun configuredStripeKey(value: String): Boolean = value.trim().startsWith("pk_")

fun configuredRealtimeUrl(value: String, requireSecureTransport: Boolean): Boolean {
    val normalized = value.trim().lowercase()
    return if (requireSecureTransport) {
        normalized.startsWith("https://") || normalized.startsWith("wss://")
    } else {
        normalized.startsWith("https://") || normalized.startsWith("wss://") ||
            normalized.startsWith("http://") || normalized.startsWith("ws://")
    }
}

fun configuredValue(value: String, fallback: String): String = value.trim().ifBlank { fallback }

fun loadLocalProperties(fileName: String): Properties {
    val file = rootProject.file(fileName)
    return Properties().apply {
        if (file.isFile) file.inputStream().use { input -> load(input) }
    }
}

fun flavorProperty(flavor: String, properties: Properties, name: String): String =
    providers.gradleProperty("NETWORKPEER_${flavor}_$name").orNull
        ?: properties.getProperty(name).orEmpty()

fun googleServicesConfigExistsForTask(taskName: String): Boolean = when {
    taskName.contains("Development", ignoreCase = true) -> developmentGoogleServices.isFile
    taskName.contains("Production", ignoreCase = true) -> productionGoogleServices.isFile
    else -> false
}

apply(plugin = "com.google.gms.google-services")
tasks.configureEach {
    if (name.startsWith("process") && name.endsWith("GoogleServices")) {
        val taskName = name
        onlyIf { googleServicesConfigExistsForTask(taskName) }
    }
}

android {
    namespace = "com.networkpeer.mobile"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.networkpeer.mobile"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

    }

    flavorDimensions += "environment"
    productFlavors {
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"

            val apiUrl = configuredValue(
                flavorProperty("DEVELOPMENT", developmentProperties, "API_BASE_URL"),
                defaultBackendApiUrl,
            )
            val stripeKey = configuredValue(
                flavorProperty("DEVELOPMENT", developmentProperties, "STRIPE_PUBLISHABLE_KEY"),
                "pk_test_sample",
            )
            val realtimeUrl = configuredValue(
                flavorProperty("DEVELOPMENT", developmentProperties, "REALTIME_URL"),
                defaultBackendRealtimeUrl,
            )
            val realtimeOrigin = configuredValue(
                flavorProperty("DEVELOPMENT", developmentProperties, "REALTIME_ORIGIN"),
                defaultBackendRealtimeOrigin,
            )

            buildConfigField("String", "NETWORKPEER_API_BASE_URL", apiUrl.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_API_CONFIGURED", configuredApiUrl(apiUrl).toString())
            buildConfigField("String", "NETWORKPEER_STRIPE_PUBLISHABLE_KEY", stripeKey.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_STRIPE_CONFIGURED", configuredStripeKey(stripeKey).toString())
            buildConfigField("String", "NETWORKPEER_REALTIME_URL", realtimeUrl.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_REALTIME_CONFIGURED", configuredRealtimeUrl(realtimeUrl, requireSecureTransport = false).toString())
            buildConfigField("boolean", "NETWORKPEER_REALTIME_SECURE_TRANSPORT_REQUIRED", "false")
            buildConfigField("String", "NETWORKPEER_REALTIME_ORIGIN", realtimeOrigin.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_FCM_CONFIGURED", developmentGoogleServices.isFile.toString())
        }
        create("production") {
            dimension = "environment"

            val apiUrl = configuredValue(
                flavorProperty("PRODUCTION", productionProperties, "API_BASE_URL"),
                defaultBackendApiUrl,
            )
            val stripeKey = configuredValue(
                flavorProperty("PRODUCTION", productionProperties, "STRIPE_PUBLISHABLE_KEY"),
                "pk_live_sample",
            )
            val realtimeUrl = configuredValue(
                flavorProperty("PRODUCTION", productionProperties, "REALTIME_URL"),
                defaultBackendRealtimeUrl,
            )
            val realtimeOrigin = configuredValue(
                flavorProperty("PRODUCTION", productionProperties, "REALTIME_ORIGIN"),
                defaultBackendRealtimeOrigin,
            )

            buildConfigField("String", "NETWORKPEER_API_BASE_URL", apiUrl.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_API_CONFIGURED", configuredApiUrl(apiUrl).toString())
            buildConfigField("String", "NETWORKPEER_STRIPE_PUBLISHABLE_KEY", stripeKey.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_STRIPE_CONFIGURED", configuredStripeKey(stripeKey).toString())
            buildConfigField("String", "NETWORKPEER_REALTIME_URL", realtimeUrl.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_REALTIME_CONFIGURED", configuredRealtimeUrl(realtimeUrl, requireSecureTransport = true).toString())
            buildConfigField("boolean", "NETWORKPEER_REALTIME_SECURE_TRANSPORT_REQUIRED", "true")
            buildConfigField("String", "NETWORKPEER_REALTIME_ORIGIN", realtimeOrigin.asBuildConfigString())
            buildConfigField("boolean", "NETWORKPEER_FCM_CONFIGURED", productionGoogleServices.isFile.toString())
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.02.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.activity:activity-compose:1.10.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.8")

    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    implementation("com.stripe:stripe-android:23.16.0")
    implementation(platform("com.google.firebase:firebase-bom:34.18.0"))
    implementation("com.google.firebase:firebase-messaging")
    implementation("io.socket:socket.io-client:2.1.2") {
        exclude(group = "org.json", module = "json")
    }

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.jakewharton.retrofit:retrofit2-kotlinx-serialization-converter:1.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.0")

    testImplementation("junit:junit:4.13.2")
}
