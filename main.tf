locals {
  defaults_firewall_rule = {
    name        = "UNKNOWN",
    id          = "UNKNOWN",
    environment = "UNKNOWN",
    prefix      = "UNKNOWN"
    priority    = 1000,
    disabled    = false,
    direction   = "ingress",
    log_config  = "DISABLED",
  }

  _firewall_rules = [for firewall_rule in var.firewall_rules : {
    name        = try(firewall_rule.name, local.defaults_firewall_rule.name)
    description = try(firewall_rule.description, firewall_rule.id, null)
    id          = try(firewall_rule.id, local.defaults_firewall_rule.id)

    project_id  = try(firewall_rule.project_id, var.project_id)
    prefix      = try(firewall_rule.prefix, var.prefix != null ? var.prefix : local.defaults_firewall_rule.prefix)
    environment = try(firewall_rule.environment, var.environment != null ? var.environment : local.defaults_firewall_rule.environment)

    network = try(firewall_rule.network, var.network)

    priority    = try(firewall_rule.priority, local.defaults_firewall_rule.priority)
    rule_action = lower(firewall_rule.action)

    rule_direction = upper(try(firewall_rule.direction, local.defaults_firewall_rule.direction))
    disabled       = try(firewall_rule.disabled, local.defaults_firewall_rule.disabled)

    source_service_accounts = [for x in firewall_rule.sources : x if length(split("@", x)) > 1 && !can(cidrnetmask(x))]
    source_tags             = [for x in firewall_rule.sources : x if length(split("@", x)) < 2 && !can(cidrnetmask(x))]
    source_cidrs            = [for x in firewall_rule.sources : x if can(cidrnetmask(x))]

    target_service_accounts = [for x in firewall_rule.targets : x if length(split("@", x)) > 1 && !can(cidrnetmask(x))]
    target_tags             = [for x in firewall_rule.targets : x if length(split("@", x)) < 2 && !can(cidrnetmask(x))]
    target_cidrs            = [for x in firewall_rule.targets : x if can(cidrnetmask(x))]


    log_config = try(upper(firewall_rule.log_config), local.defaults_firewall_rule.log_config)
    rules      = try(firewall_rule.rules, null)
  }]

  firewall_rules = { for firewall_rule in local._firewall_rules : format("fw-r-%s", uuidv5("x500",
    format("PREFIX=%s,ENVIRONMENT=%s,PROJECT_ID=%s,NETWORK=%s,NAME=%s,ID=%s",
      firewall_rule.prefix,
      firewall_rule.environment,
      firewall_rule.project_id,
      firewall_rule.network,
      firewall_rule.name,
      firewall_rule.id,
    ))) => merge(firewall_rule, {
    source_ranges = length(concat(firewall_rule.source_service_accounts, firewall_rule.source_tags, firewall_rule.source_cidrs)) > 0 ? firewall_rule.source_cidrs : ["0.0.0.0/0"]
    target_ranges = length(concat(firewall_rule.target_service_accounts, firewall_rule.target_tags, firewall_rule.target_cidrs)) > 0 ? firewall_rule.target_cidrs : ["0.0.0.0/0"]
    })

  }
}

resource "google_compute_firewall" "firewall_rule" {
  for_each = local.firewall_rules
  name     = each.value.name != local.defaults_firewall_rule.name ? each.value.name : each.key
  project  = each.value.project_id
  network  = each.value.network

  direction = each.value.rule_direction
  disabled  = each.value.disabled
  priority  = each.value.priority

  description        = try(each.value.description, null)
  source_ranges      = length(each.value.source_ranges) > 0 && each.value.rule_direction == "INGRESS" ? each.value.source_ranges : length(each.value.source_ranges) == 0 && each.value.rule_direction == "INGRESS" ? [] : null
  destination_ranges = length(each.value.target_ranges) > 0 && each.value.rule_direction == "EGRESS" ? each.value.target_ranges : length(each.value.target_ranges) == 0 && each.value.rule_direction == "EGRESS" ? [] : null

  source_tags             = length(each.value.source_tags) > 0 && each.value.rule_direction == "INGRESS" ? each.value.source_tags : null
  source_service_accounts = length(each.value.source_service_accounts) > 0 && each.value.rule_direction == "INGRESS" ? each.value.source_service_accounts : null
  target_tags             = length(each.value.target_tags) > 0 && each.value.rule_direction == "INGRESS" ? each.value.target_tags : length(each.value.source_tags) > 0 && each.value.rule_direction == "EGRESS" ? each.value.source_tags : null
  target_service_accounts = length(each.value.target_service_accounts) > 0 && each.value.rule_direction == "INGRESS" ? each.value.target_service_accounts : length(each.value.source_service_accounts) > 0 && each.value.rule_direction == "EGRESS" ? each.value.source_service_accounts : null

  dynamic "log_config" {
    for_each = each.value.log_config != "DISABLED" ? [1] : []
    content {
      metadata = each.value.log_config
    }
  }

  dynamic "allow" {
    for_each = [for rule in each.value.rules : rule if each.value.rule_action == "allow"]
    iterator = rule
    content {
      protocol = lower(rule.value.protocol)
      ports    = concat(try(rule.value.ports, []), try(rule.value.port_ranges, []))
    }
  }
  dynamic "deny" {
    for_each = [for rule in each.value.rules : rule if each.value.rule_action == "deny"]
    iterator = rule
    content {
      protocol = lower(rule.value.protocol)
      ports    = concat(try(rule.value.ports, []), try(rule.value.port_ranges, []))
    }
  }
}