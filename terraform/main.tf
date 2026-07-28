terraform {
  required_version = ">= 1.5.0"
  required_providers {
    zitadel = {
      source  = "zitadel/zitadel"
      version = ">= 2.0.0, < 3.0.0"
    }
  }
}

provider "zitadel" {
  domain       = var.zitadel_domain
  port         = var.zitadel_port
  insecure     = var.zitadel_insecure
  access_token = var.zitadel_token
}

variable "zitadel_domain" {
  type        = string
  description = "FQDN of self-hosted Zitadel (no scheme). From env ZITADEL_DOMAIN / secrets."
  default     = "auth.example.com"
}

variable "zitadel_token" {
  type        = string
  sensitive   = true
  description = "Machine user PAT. From env ZITADEL_TOKEN — never commit."
  default     = "unset"
}

variable "zitadel_org_id" {
  type        = string
  description = "Owner org id (product). From env ZITADEL_ORG_ID."
  default     = "0"
}

variable "zitadel_port" {
  type    = string
  default = "443"
}

variable "zitadel_insecure" {
  type    = bool
  default = false
}

variable "native_redirect_uris" {
  type = list(string)
  default = [
    "masterdoc://auth/callback",
    "http://127.0.0.1:8081/callback",
  ]
  description = "KMP native / desktop redirect URIs (adjust per app)."
}

variable "web_redirect_uris" {
  type = list(string)
  default = [
    "https://copilot.fixaverse.ru/auth/callback",
    "https://app.fixaverse.ru/auth/callback",
    "http://localhost:8080/auth/callback",
  ]
  description = "Wasm / web redirect URIs."
}

variable "web_post_logout_redirect_uris" {
  type = list(string)
  default = [
    "https://copilot.fixaverse.ru/",
    "https://app.fixaverse.ru/",
    "http://localhost:8080/",
  ]
}

locals {
  # Zitadel role_key values = product feature wires (see feature-service catalog).
  roles = {
    admin     = "Admin"
    black_box = "Black box"
    board     = "Board"
    charts    = "ППР"
    engineer  = "Engineer"
    equipment = "Equipment"
  }
}

resource "zitadel_project" "toir" {
  name                   = "masterdoc-toir"
  org_id                 = var.zitadel_org_id
  project_role_assertion = true
  project_role_check     = true
  has_project_check      = true
}

resource "zitadel_project_role" "roles" {
  for_each     = local.roles
  org_id       = var.zitadel_org_id
  project_id   = zitadel_project.toir.id
  role_key     = each.key
  display_name = each.value
}

resource "zitadel_application_oidc" "native" {
  org_id                       = var.zitadel_org_id
  project_id                   = zitadel_project.toir.id
  name                         = "masterdoc-kmp-native"
  redirect_uris                = var.native_redirect_uris
  post_logout_redirect_uris    = var.native_redirect_uris
  response_types               = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                  = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                     = "OIDC_APP_TYPE_NATIVE"
  auth_method_type             = "OIDC_AUTH_METHOD_TYPE_NONE"
  version                      = "OIDC_VERSION_1_0"
  clock_skew                   = "0s"
  dev_mode                     = true
  access_token_type            = "OIDC_TOKEN_TYPE_JWT"
  access_token_role_assertion  = true
  id_token_role_assertion      = true
  id_token_userinfo_assertion  = true
  skip_native_app_success_page = true

  depends_on = [zitadel_project_role.roles]
}

resource "zitadel_application_oidc" "web" {
  org_id                      = var.zitadel_org_id
  project_id                  = zitadel_project.toir.id
  name                        = "masterdoc-kmp-web"
  redirect_uris               = var.web_redirect_uris
  post_logout_redirect_uris   = var.web_post_logout_redirect_uris
  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                    = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_NONE"
  version                     = "OIDC_VERSION_1_0"
  clock_skew                  = "0s"
  dev_mode                    = true
  access_token_type           = "OIDC_TOKEN_TYPE_JWT"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true

  depends_on = [zitadel_project_role.roles]
}

# Instance default redirect is managed by scripts/ensure-login-local-email.sh /
# ensure-default-redirect.sh (do not partial-merge GET→PUT — it can flip flags).
# Org login policy: local email+password, no self-signup, redirect to app.
resource "zitadel_login_policy" "no_self_signup" {
  org_id                        = var.zitadel_org_id
  user_login                    = true
  allow_register                = false
  allow_external_idp            = false
  force_mfa                     = false
  force_mfa_local_only          = false
  passwordless_type             = "PASSWORDLESS_TYPE_NOT_ALLOWED"
  hide_password_reset           = false
  ignore_unknown_usernames      = true
  default_redirect_uri          = "https://app.fixaverse.ru/"
  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  multi_factor_check_lifetime   = "24h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "24h0m0s"
  allow_domain_discovery        = false
  disable_login_with_email      = false
  disable_login_with_phone      = true
  second_factors                = []
  multi_factors                 = []
  idps                          = []
}

# Instance default: password = min length only (demo / invite UX).
resource "zitadel_default_password_complexity_policy" "default" {
  min_length    = 8
  has_uppercase = false
  has_lowercase = false
  has_number    = false
  has_symbol    = false
}

output "project_id" {
  value = zitadel_project.toir.id
}

output "native_client_id" {
  value     = zitadel_application_oidc.native.client_id
  sensitive = true
}

output "web_client_id" {
  value     = zitadel_application_oidc.web.client_id
  sensitive = true
}

output "role_keys" {
  value = keys(local.roles)
}
