plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
}

gradlePlugin {
    plugins {
        register("nativeLoad") {
            id = "dev.oxyroid.native-load"
            implementationClass = "dev.oxyroid.nativeload.NativeLoadPlugin"
        }
    }
}

dependencies {
    implementation("com.android.tools.build:gradle-api:${libs.versions.android.gradle.plugin.get()}")
    implementation(libs.snakeyaml)
}