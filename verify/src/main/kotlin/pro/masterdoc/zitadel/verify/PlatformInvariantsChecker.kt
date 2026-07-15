package pro.masterdoc.zitadel.verify

class InvariantViolation(message: String) : RuntimeException(message)

class PlatformInvariantsChecker(
    private val expected: ExpectedPlatform,
    private val client: ZitadelAdminClient,
) {
    fun verify(): List<String> {
        val errors = mutableListOf<String>()

        val project = client.findProjectByName(expected.projectName)
        if (project == null) {
            errors += "missing project '${expected.projectName}'"
        } else {
            val missingRoles = expected.roles - project.roleKeys
            if (missingRoles.isNotEmpty()) {
                errors += "project '${expected.projectName}' missing roles: ${missingRoles.sorted().joinToString()}"
            }
        }

        val apps = client.listOidcApps(expected.projectName).associateBy { it.name }
        for (want in expected.oidcApps) {
            val got = apps[want.name]
            if (got == null) {
                errors += "missing OIDC app '${want.name}'"
                continue
            }
            if (got.authMethod != want.authMethod) {
                errors += "app '${want.name}' auth_method=${got.authMethod}, expected ${want.authMethod}"
            }
            val missingGrants = want.grantTypes - got.grantTypes
            if (missingGrants.isNotEmpty()) {
                errors += "app '${want.name}' missing grant_types: ${missingGrants.sorted().joinToString()}"
            }
            if (want.roleAssertion && !(got.accessTokenRoleAssertion && got.idTokenRoleAssertion)) {
                errors += "app '${want.name}' role assertion must be enabled on access and id tokens"
            }
        }

        val policy = client.getLoginPolicy()
        if (policy.allowRegister != expected.loginPolicy.allowRegister) {
            errors += "login_policy.allow_register=${policy.allowRegister}, expected ${expected.loginPolicy.allowRegister}"
        }
        if (policy.userLogin != expected.loginPolicy.userLogin) {
            errors += "login_policy.user_login=${policy.userLogin}, expected ${expected.loginPolicy.userLogin}"
        }
        if (policy.allowExternalIdp != expected.loginPolicy.allowExternalIdp) {
            errors += "login_policy.allow_external_idp=${policy.allowExternalIdp}, expected ${expected.loginPolicy.allowExternalIdp}"
        }

        return errors
    }

    fun verifyOrThrow() {
        val errors = verify()
        if (errors.isNotEmpty()) {
            throw InvariantViolation(errors.joinToString(separator = "\n"))
        }
    }
}
