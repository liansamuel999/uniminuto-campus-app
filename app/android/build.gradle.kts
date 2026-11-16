allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter lee esta propiedad para compilar los plugins (firebase_*, file_selector, etc.) con la
// misma versión de Kotlin que la app. Sin ella usa su Kotlin embebido 2.2 y falla el enlace con
// las librerías de Firebase compiladas con metadata 2.4 (D-77).
extra["kotlin_version"] = "2.4.20"

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
