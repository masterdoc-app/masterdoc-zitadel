package pro.masterdoc.zitadel.verify

import org.yaml.snakeyaml.Yaml
import java.io.Reader
import java.nio.file.Files
import java.nio.file.Path

object ExpectedLoader {
    fun load(path: Path): ExpectedPlatform =
        Files.newBufferedReader(path).use { load(it) }

    @Suppress("UNCHECKED_CAST")
    fun load(reader: Reader): ExpectedPlatform {
        val root = Yaml().load<Map<String, Any?>>(reader)
            ?: error("expected.yaml is empty")

        val roles = (root["roles"] as? List<*>)?.map { it.toString() }?.toSet()
            ?: error("roles missing")

        val apps = (root["oidc_apps"] as? List<Map<String, Any?>>)?.map { app ->
            ExpectedOidcApp(
                name = app["name"].toString(),
                authMethod = app["auth_method"].toString(),
                grantTypes = (app["grant_types"] as List<*>).map { it.toString() }.toSet(),
                roleAssertion = app["role_assertion"] as Boolean,
            )
        } ?: error("oidc_apps missing")

        val lp = root["login_policy"] as Map<String, Any?>
        return ExpectedPlatform(
            projectName = root["project_name"].toString(),
            roles = roles,
            oidcApps = apps,
            loginPolicy = ExpectedLoginPolicy(
                allowRegister = lp["allow_register"] as Boolean,
                userLogin = lp["user_login"] as Boolean,
                allowExternalIdp = lp["allow_external_idp"] as Boolean,
            ),
        )
    }
}
