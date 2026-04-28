import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

fun configValue(localKey: String, envKey: String): String {
    return (localProperties.getProperty(localKey)
        ?: System.getenv(envKey)
        ?: "").trim()
}

fun quoted(value: String): String {
    val escaped = value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
    return "\"$escaped\""
}

android {
    namespace = "com.flyr.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.flyr.android"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField("String", "SUPABASE_URL", quoted(configValue("flyr.supabase.url", "FLYR_SUPABASE_URL")))
        buildConfigField("String", "SUPABASE_ANON_KEY", quoted(configValue("flyr.supabase.anonKey", "FLYR_SUPABASE_ANON_KEY")))
        buildConfigField("String", "MAPBOX_PUBLIC_TOKEN", quoted(configValue("flyr.mapbox.publicToken", "FLYR_MAPBOX_PUBLIC_TOKEN")))
        buildConfigField("String", "FLYR_PRO_API_URL", quoted(configValue("flyr.pro.apiUrl", "FLYR_PRO_API_URL").ifEmpty { "https://flyrpro.app" }))
        buildConfigField("String", "FLYR_ENVIRONMENT", quoted(configValue("flyr.environment", "FLYR_ENVIRONMENT").ifEmpty { "development" }))
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.jb.kotlinx.coroutines.android)
    implementation(libs.google.material)
    implementation(platform(libs.supabase.bom))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.supabase.auth.kt)
    implementation(libs.ktor.client.okhttp)

    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
}
