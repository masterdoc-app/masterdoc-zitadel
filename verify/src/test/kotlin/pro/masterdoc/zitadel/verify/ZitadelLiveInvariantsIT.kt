package pro.masterdoc.zitadel.verify

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Tag
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable
import java.nio.file.Path

/**
 * Opt-in live check. Not run in default CI (`./gradlew test`).
 * Requires ZITADEL_DOMAIN, ZITADEL_TOKEN, and a Management API compatible with HttpZitadelAdminClient
 * (after terraform apply you may need a thin adapter — for MVP this documents the tag gate).
 */
@Tag("zitadel-live")
@EnabledIfEnvironmentVariable(named = "ZITADEL_TOKEN", matches = ".+")
class ZitadelLiveInvariantsIT {

    @Test
    fun `live endpoints are configured`() {
        val domain = System.getenv("ZITADEL_DOMAIN")
        val token = System.getenv("ZITADEL_TOKEN")
        assertTrue(!domain.isNullOrBlank(), "ZITADEL_DOMAIN required")
        assertTrue(!token.isNullOrBlank(), "ZITADEL_TOKEN required")

        // Live Management API shapes differ by Zitadel version; smoke that client + expected load.
        val expected = ExpectedLoader.load(Path.of("../terraform/expected.yaml"))
        assertTrue(expected.roles.contains("board"))
        assertTrue(expected.roles.contains("user_invite"))
    }
}
