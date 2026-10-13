allprojects {
    repositories {
        exclusiveContent {
            forRepository {
                maven {
                    name = "FlutterEngineOfficial"
                    url = uri("https://storage.googleapis.com/download.flutter.io")
                }
            }
            filter { includeGroup("io.flutter") }
        }
        maven(url = "https://maven-central.storage-download.googleapis.com/maven2/")
        google()
        mavenCentral()
    }
}

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
