plugins {
    kotlin("jvm")
    kotlin("plugin.spring")
    kotlin("plugin.jpa")
    id("org.springframework.boot")
    id("io.spring.dependency-management")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_25)
        freeCompilerArgs.add("-Xjsr305=strict")
    }
}

dependencies {
    implementation(project(":library"))
    implementation(project(":settings"))
    implementation(project(":auth"))
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    implementation("org.springframework.boot:spring-boot-starter-flyway")
    implementation("org.flywaydb:flyway-mysql")
    implementation("org.jetbrains.kotlin:kotlin-reflect")
    runtimeOnly("com.mysql:mysql-connector-j")

    testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
}

tasks.withType<Test> {
    useJUnitPlatform()
}

springBoot {
    mainClass.set("com.scatl.folio.FolioApplication")
}

val webProjectDir = rootProject.projectDir.resolve("../Folio-Web")
val skipWebBuild = providers.gradleProperty("skipWebBuild")
    .orElse(providers.environmentVariable("SKIP_WEB_BUILD"))
    .map { it.equals("true", ignoreCase = true) || it == "1" }
    .orElse(false)

val npmCommand = if (System.getProperty("os.name").lowercase().contains("windows")) {
    listOf("npm.cmd")
} else {
    listOf("npm")
}

val installWeb = tasks.register<Exec>("installWeb") {
    group = "build"
    onlyIf { !skipWebBuild.get() && webProjectDir.resolve("package.json").exists() }
    workingDir = webProjectDir
    commandLine(npmCommand + listOf("ci"))
    inputs.files(
        webProjectDir.resolve("package.json"),
        webProjectDir.resolve("package-lock.json"),
    )
    outputs.dir(webProjectDir.resolve("node_modules"))
}

val buildWeb = tasks.register<Exec>("buildWeb") {
    group = "build"
    dependsOn(installWeb)
    onlyIf { !skipWebBuild.get() && webProjectDir.resolve("package.json").exists() }
    workingDir = webProjectDir
    commandLine(npmCommand + listOf("run", "build"))
    inputs.dir(webProjectDir.resolve("src"))
    inputs.files(
        webProjectDir.resolve("index.html"),
        webProjectDir.resolve("vite.config.ts"),
        webProjectDir.resolve("package.json"),
        webProjectDir.resolve("tsconfig.json"),
        webProjectDir.resolve("tsconfig.app.json"),
    )
    outputs.dir(webProjectDir.resolve("dist"))
}

val copyWeb = tasks.register<Copy>("copyWeb") {
    group = "build"
    dependsOn(buildWeb)
    onlyIf { webProjectDir.resolve("dist/index.html").exists() }
    from(webProjectDir.resolve("dist"))
    into(layout.buildDirectory.dir("resources/main/static"))
    // Keep server-bundled provider logos under assets/providers
    duplicatesStrategy = DuplicatesStrategy.INCLUDE
}

tasks.named("processResources") {
    finalizedBy(copyWeb)
}

tasks.named("classes") {
    dependsOn(copyWeb)
}
