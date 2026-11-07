import com.android.build.api.variant.LibraryAndroidComponentsExtension

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Legacy transitive plugins use old SDK defaults. Configure their DSL through
// AGP's supported finalization hook before creating variants (fixture only).
subprojects {
    val libraryProject = this
    pluginManager.withPlugin("com.android.library") {
        libraryProject.extensions.getByType<LibraryAndroidComponentsExtension>().finalizeDsl {
            it.compileSdk = 36
        }
    }
}

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

