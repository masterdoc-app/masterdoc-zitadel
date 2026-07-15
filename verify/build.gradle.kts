plugins {
    kotlin("jvm") version "2.0.21"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(kotlin("stdlib"))
    implementation("org.yaml:snakeyaml:2.3")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.code.gson:gson:2.11.0")

    testImplementation(kotlin("test-junit5"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.3")
    testImplementation("org.wiremock:wiremock:3.9.1")
}

tasks.test {
    useJUnitPlatform {
        excludeTags("zitadel-live")
    }
}

tasks.register<Test>("liveTest") {
    description = "Run live invariant checks against a real Zitadel (needs ZITADEL_TOKEN)."
    group = "verification"
    useJUnitPlatform {
        includeTags("zitadel-live")
    }
    testClassesDirs = tasks.test.get().testClassesDirs
    classpath = tasks.test.get().classpath
}

kotlin {
    jvmToolchain(17)
}
