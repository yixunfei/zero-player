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
    project.evaluationDependsOn(":app")
    if (name == "pdfium_flutter") {
        // AGP on Windows does not discover this plugin's generated directory symlink.
        // Use its pinned release directory and verify the binaries before packaging.
        afterEvaluate {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                sourceSets.getByName("main").jniLibs.setSrcDirs(listOf(file(".lib/chromium%2F7520")))
            }
            tasks.matching { it.name.startsWith("merge") && it.name.endsWith("JniLibFolders") }.configureEach {
                doFirst {
                    val hashes = mapOf(
                        "arm64-v8a" to "956f2684d697396ef7d201509005d123d0367b1f619cdd23c94e1430811984bf",
                        "x86_64" to "a21a319480ca8a32ec64a47a657689ee4444b813819edcc2c3941335f973928e"
                    )
                    for ((abi, expected) in hashes) {
                        val library = file(".lib/chromium%2F7520/$abi/libpdfium.so")
                        check(library.exists()) { "Missing pinned PDFium for $abi" }
                        val hash = java.security.MessageDigest.getInstance("SHA-256").digest(library.readBytes())
                            .joinToString("") { "%02x".format(it) }
                        check(hash == expected) { "PDFium checksum mismatch for $abi" }
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
