# JSch instantiates ciphers, KEX, MACs and signatures by class name
-keep class com.jcraft.jsch.** { *; }

# Optional JSch integrations not shipped with the app
-dontwarn org.bouncycastle.**
-dontwarn org.newsclub.net.unix.**
-dontwarn com.sun.jna.**
-dontwarn org.slf4j.**
-dontwarn org.apache.logging.log4j.**
-dontwarn org.ietf.jgss.**
-dontwarn javax.security.auth.**
