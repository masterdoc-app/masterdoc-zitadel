package pro.masterdoc.zitadel.verify

import com.google.gson.Gson
import com.google.gson.JsonObject
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Thin Management-API shaped client used by unit (WireMock) and optional live tests.
 * Paths are stable fixtures under /management/v1/... for contract testing.
 */
class HttpZitadelAdminClient(
    private val baseUrl: String,
    private val token: String,
    private val http: OkHttpClient = OkHttpClient(),
    private val gson: Gson = Gson(),
) : ZitadelAdminClient {

    override fun findProjectByName(name: String): ActualProject? {
        val body = getJson("/management/v1/projects/_search")
        val projects = body.getAsJsonArray("result") ?: return null
        for (el in projects) {
            val obj = el.asJsonObject
            if (obj.get("name")?.asString == name) {
                val roles = obj.getAsJsonArray("roleKeys")
                    ?.map { it.asString }
                    ?.toSet()
                    ?: emptySet()
                return ActualProject(name = name, roleKeys = roles)
            }
        }
        return null
    }

    override fun listOidcApps(projectName: String): List<ActualOidcApp> {
        val body = getJson("/management/v1/projects/$projectName/apps/oidc")
        val apps = body.getAsJsonArray("result") ?: return emptyList()
        return apps.map { el ->
            val obj = el.asJsonObject
            ActualOidcApp(
                name = obj.get("name").asString,
                authMethod = obj.get("authMethod").asString,
                grantTypes = obj.getAsJsonArray("grantTypes").map { it.asString }.toSet(),
                accessTokenRoleAssertion = obj.get("accessTokenRoleAssertion").asBoolean,
                idTokenRoleAssertion = obj.get("idTokenRoleAssertion").asBoolean,
            )
        }
    }

    override fun getLoginPolicy(): ActualLoginPolicy {
        val obj = getJson("/management/v1/policies/login")
        return ActualLoginPolicy(
            allowRegister = obj.get("allowRegister").asBoolean,
            userLogin = obj.get("userLogin").asBoolean,
            allowExternalIdp = obj.get("allowExternalIdp").asBoolean,
        )
    }

    private fun getJson(path: String): JsonObject {
        val request = Request.Builder()
            .url(baseUrl.trimEnd('/') + path)
            .header("Authorization", "Bearer $token")
            .get()
            .build()
        http.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            check(response.isSuccessful) { "HTTP ${response.code} for $path: $text" }
            return gson.fromJson(text, JsonObject::class.java)
        }
    }
}
