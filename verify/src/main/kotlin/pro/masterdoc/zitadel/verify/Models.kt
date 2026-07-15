package pro.masterdoc.zitadel.verify

data class ExpectedPlatform(
    val projectName: String,
    val roles: Set<String>,
    val oidcApps: List<ExpectedOidcApp>,
    val loginPolicy: ExpectedLoginPolicy,
)

data class ExpectedOidcApp(
    val name: String,
    val authMethod: String,
    val grantTypes: Set<String>,
    val roleAssertion: Boolean,
)

data class ExpectedLoginPolicy(
    val allowRegister: Boolean,
    val userLogin: Boolean,
    val allowExternalIdp: Boolean,
)

data class ActualProject(val name: String, val roleKeys: Set<String>)

data class ActualOidcApp(
    val name: String,
    val authMethod: String,
    val grantTypes: Set<String>,
    val accessTokenRoleAssertion: Boolean,
    val idTokenRoleAssertion: Boolean,
)

data class ActualLoginPolicy(
    val allowRegister: Boolean,
    val userLogin: Boolean,
    val allowExternalIdp: Boolean,
)

interface ZitadelAdminClient {
    fun findProjectByName(name: String): ActualProject?
    fun listOidcApps(projectName: String): List<ActualOidcApp>
    fun getLoginPolicy(): ActualLoginPolicy
}
