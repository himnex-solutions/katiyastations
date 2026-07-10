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

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    // Compatibility shim for Flutter plugins that predate the current AGP.
    // Must be registered before evaluationDependsOn below, which evaluates :app eagerly.
    afterEvaluate {
        val libraryExtension =
            extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
                ?: return@afterEvaluate

        // Plugins published before AGP 8 declare their namespace via the AndroidManifest
        // `package` attribute, which AGP no longer reads. Backfill it from the Gradle group.
        if (libraryExtension.namespace == null) {
            libraryExtension.namespace = project.group.toString()
        }

        // Several plugins pin a compileSdk older than the one their own transitive
        // dependencies now require, which fails the AAR metadata check. Raise them to
        // the app's compileSdk; this does not affect minSdk or targetSdk.
        val appCompileSdk =
            rootProject.project(":app").extensions
                .findByType(com.android.build.api.dsl.ApplicationExtension::class.java)
                ?.compileSdk
        if (appCompileSdk != null && (libraryExtension.compileSdk ?: 0) < appCompileSdk) {
            libraryExtension.compileSdk = appCompileSdk
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
