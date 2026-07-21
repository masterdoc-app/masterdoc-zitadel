package pro.masterdoc.zitadel.verify

import com.github.tomakehurst.wiremock.WireMockServer
import com.github.tomakehurst.wiremock.client.WireMock.aResponse
import com.github.tomakehurst.wiremock.client.WireMock.get
import com.github.tomakehurst.wiremock.client.WireMock.urlEqualTo
import com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import java.nio.file.Path

class ZitadelInvariantsTest {

    private lateinit var server: WireMockServer
    private lateinit var expected: ExpectedPlatform

    @BeforeEach
    fun setUp() {
        expected = ExpectedLoader.load(Path.of("../terraform/expected.yaml"))
        server = WireMockServer(wireMockConfig().dynamicPort())
        server.start()
    }

    @AfterEach
    fun tearDown() {
        server.stop()
    }

    @Test
    fun `fails when board feature key is missing`() {
        stubProject(roleKeys = listOf("charts", "copilot", "equipment", "user_invite"))
        stubApps(okAppsJson())
        stubLoginPolicy(allowRegister = false)

        val errors = checker().verify()

        assertTrue(errors.any { it.contains("missing roles") && it.contains("board") }, errors.toString())
    }

    @Test
    fun `fails when self-signup is enabled`() {
        stubProject(roleKeys = expected.roles.toList())
        stubApps(okAppsJson())
        stubLoginPolicy(allowRegister = true)

        val errors = checker().verify()

        assertTrue(errors.any { it.contains("allow_register=true") }, errors.toString())
    }

    @Test
    fun `fails when grant types miss refresh_token`() {
        stubProject(roleKeys = expected.roles.toList())
        stubApps(
            """
            {"result":[
              {"name":"masterdoc-kmp-native","authMethod":"none",
               "grantTypes":["authorization_code"],
               "accessTokenRoleAssertion":true,"idTokenRoleAssertion":true},
              {"name":"masterdoc-kmp-web","authMethod":"none",
               "grantTypes":["authorization_code","refresh_token"],
               "accessTokenRoleAssertion":true,"idTokenRoleAssertion":true}
            ]}
            """.trimIndent(),
        )
        stubLoginPolicy(allowRegister = false)

        val errors = checker().verify()

        assertTrue(errors.any { it.contains("masterdoc-kmp-native") && it.contains("refresh_token") }, errors.toString())
    }

    @Test
    fun `passes when platform matches expected yaml`() {
        stubProject(roleKeys = expected.roles.toList())
        stubApps(okAppsJson())
        stubLoginPolicy(allowRegister = false)

        checker().verifyOrThrow()
    }

    @Test
    fun `verifyOrThrow raises InvariantViolation`() {
        stubProject(roleKeys = emptyList())
        stubApps("""{"result":[]}""")
        stubLoginPolicy(allowRegister = true)

        assertThrows<InvariantViolation> { checker().verifyOrThrow() }
    }

    private fun checker() =
        PlatformInvariantsChecker(
            expected = expected,
            client = HttpZitadelAdminClient(baseUrl = server.baseUrl(), token = "test-token"),
        )

    private fun stubProject(roleKeys: List<String>) {
        val rolesJson = roleKeys.joinToString(prefix = "[", postfix = "]") { "\"$it\"" }
        server.stubFor(
            get(urlEqualTo("/management/v1/projects/_search")).willReturn(
                aResponse()
                    .withHeader("Content-Type", "application/json")
                    .withBody(
                        """
                        {"result":[{"name":"masterdoc-toir","roleKeys":$rolesJson}]}
                        """.trimIndent(),
                    ),
            ),
        )
    }

    private fun stubApps(body: String) {
        server.stubFor(
            get(urlEqualTo("/management/v1/projects/masterdoc-toir/apps/oidc")).willReturn(
                aResponse()
                    .withHeader("Content-Type", "application/json")
                    .withBody(body),
            ),
        )
    }

    private fun stubLoginPolicy(allowRegister: Boolean) {
        server.stubFor(
            get(urlEqualTo("/management/v1/policies/login")).willReturn(
                aResponse()
                    .withHeader("Content-Type", "application/json")
                    .withBody(
                        """
                        {"allowRegister":$allowRegister,"userLogin":true,"allowExternalIdp":false}
                        """.trimIndent(),
                    ),
            ),
        )
    }

    private fun okAppsJson(): String =
        """
        {"result":[
          {"name":"masterdoc-kmp-native","authMethod":"none",
           "grantTypes":["authorization_code","refresh_token"],
           "accessTokenRoleAssertion":true,"idTokenRoleAssertion":true},
          {"name":"masterdoc-kmp-web","authMethod":"none",
           "grantTypes":["authorization_code","refresh_token"],
           "accessTokenRoleAssertion":true,"idTokenRoleAssertion":true}
        ]}
        """.trimIndent()
}
