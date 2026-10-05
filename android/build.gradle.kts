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
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                val getNamespace = android.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(android) == null) {
                    val fallbackNamespace = if (name == "on_audio_query_android") {
                        "com.lucasjosino.on_audio_query"
                    } else {
                        "com.example.${name.replace('-', '_')}"
                    }
                    setNamespace.invoke(android, fallbackNamespace)
                }
            } catch (_: Throwable) {}
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
