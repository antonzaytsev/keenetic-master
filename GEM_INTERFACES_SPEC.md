# Interfaces to Add to `keenetic` Gem

This document specifies the interfaces needed to fully support keenetic-master project.

## 1. Routes Module (`client.routes`)

### `client.routes.all`
Returns all static routes from router configuration.

**RCI Request:**
```json
[{"show": {"sc": {"ip": {"route": {}}}}}]
```

**Response path:** `[0]['show']['sc']['ip']['route']`

**Returns:** Array of route hashes with keys:
- `network` (String) - Network address
- `mask` (String) - Subnet mask
- `host` (String) - Single host IP (for /32 routes)
- `interface` (String) - Interface name
- `gateway` (String) - Gateway address
- `comment` (String) - Route description
- `auto` (Boolean)
- `reject` (Boolean)

---

### `client.routes.add(route_params)`
Adds a single static route.

**Parameters:**
```ruby
{
  host: "1.2.3.4",           # Single IP (mutually exclusive with network/mask)
  # OR
  network: "10.0.0.0",       # Network address
  mask: "255.255.255.0",     # Subnet mask (or accept CIDR and convert)
  
  interface: "Wireguard0",   # Required - interface name
  comment: "Route comment",  # Required - description
  gateway: "",               # Optional, default ""
  auto: true,                # Optional, default true
  reject: false              # Optional, default false
}
```

**RCI Request:**
```json
[
  {"webhelp": {"event": {"push": {"data": "{\"type\":\"configuration_change\",\"value\":{\"url\":\"/staticRoutes\"}}"}}}},
  {"ip": {"route": {"host|network": "...", "mask": "...", "interface": "...", "gateway": "", "auto": true, "reject": false, "comment": "..."}}},
  {"system": {"configuration": {"save": {}}}}
]
```

**Response validation:** Check `ip.route.status[0].status` != "error"

---

### `client.routes.add_batch(routes_array)`
Adds multiple routes in single request.

**Parameters:** Array of route hashes (same as `add`)

**RCI Request:**
```json
[
  {"webhelp": {"event": {"push": {"data": "..."}}}},
  {"ip": {"route": {...}}},
  {"ip": {"route": {...}}},
  {"ip": {"route": {...}}},
  {"system": {"configuration": {"save": {}}}}
]
```

---

### `client.routes.delete(route_params)`
Deletes a single static route.

**Parameters:**
```ruby
{
  host: "1.2.3.4",       # Single IP
  # OR
  network: "10.0.0.0",
  mask: "255.255.255.0"
}
```

**RCI Request:**
```json
[
  {"webhelp": {"event": {"push": {"data": "..."}}}},
  {"ip": {"route": {"no": true, "host|network": "...", "mask": "..."}}},
  {"system": {"configuration": {"save": {}}}}
]
```

---

### `client.routes.delete_batch(routes_array)`
Deletes multiple routes in single request.

---

## 2. Hotspot/Policy Module (`client.hotspot`)

### `client.hotspot.policies`
Returns all IP policies.

**RCI Request:**
```json
[{"show": {"sc": {"ip": {"policy": {}}}}}]
```

**Response path:** `[0]['show']['sc']['ip']['policy']`

---

### `client.hotspot.hosts`
Returns all registered hosts with their policies.

**RCI Request:**
```json
[
  {"show": {"sc": {"ip": {"hotspot": {"host": {}}}}}},
  {"show": {"ip": {"hotspot": {}}}}
]
```

**Response paths:**
- Config hosts: `['show']['sc']['ip']['hotspot']['host']`
- Runtime hosts: `['show']['ip']['hotspot']['host']`

---

### `client.hotspot.set_host_policy(mac:, policy:, permit: true)`
Sets or removes policy for a host.

**Parameters:**
```ruby
{
  mac: "AA:BB:CC:DD:EE:FF",  # Required - client MAC address
  policy: "Policy0",         # Policy name, or {no: true} to remove
  permit: true               # Optional, default true
}
```

**RCI Request:**
```json
[
  {"webhelp": {"event": {"push": {"data": "{\"type\":\"configuration_change\",\"value\":{\"url\":\"/policies/policy-consumers\"}}"}}}},
  {"ip": {"hotspot": {"host": {"mac": "...", "permit": true, "policy": "..."}}}},
  {"system": {"configuration": {"save": {}}}}
]
```

---

## 3. Configuration Module (`client.config`)

### `client.config.save`
Saves current configuration to persistent storage.

**RCI Request:**
```json
[{"system": {"configuration": {"save": {}}}}]
```

---

### `client.config.download`
Downloads startup configuration file.

**HTTP Request:** `GET /ci/startup-config.txt`

**Returns:** String (configuration file content)

---

## 4. Raw RCI Access (`client.rci`)

### `client.rci(body)`
Executes arbitrary RCI command(s).

**Parameters:** Hash or Array of hashes (RCI commands)

**Returns:** Parsed JSON response

This enables custom commands without gem changes.

---

## 5. Utility: CIDR to Mask Conversion

The gem should handle CIDR notation internally:

```ruby
# User can pass either:
client.routes.add(host: "10.0.0.0/24", ...)
# OR
client.routes.add(network: "10.0.0.0", mask: "255.255.255.0", ...)
```

**CIDR to Mask mapping:**
```ruby
CIDR_TO_MASK = {
  8  => '255.0.0.0',
  16 => '255.255.0.0',
  17 => '255.255.128.0',
  18 => '255.255.192.0',
  19 => '255.255.224.0',
  20 => '255.255.240.0',
  21 => '255.255.248.0',
  22 => '255.255.252.0',
  23 => '255.255.254.0',
  24 => '255.255.255.0',
  25 => '255.255.255.128',
  26 => '255.255.255.192',
  27 => '255.255.255.224',
  28 => '255.255.255.240',
  29 => '255.255.255.248',
  30 => '255.255.255.252',
  31 => '255.255.255.254',
  32 => '255.255.255.255'
}
```

---

## Summary Table

| Module | Method | Priority |
|--------|--------|----------|
| `routes` | `all` | High |
| `routes` | `add(params)` | High |
| `routes` | `add_batch(array)` | High |
| `routes` | `delete(params)` | High |
| `routes` | `delete_batch(array)` | High |
| `hotspot` | `policies` | Medium |
| `hotspot` | `hosts` | Medium |
| `hotspot` | `set_host_policy(...)` | Medium |
| `config` | `save` | High |
| `config` | `download` | Low |
| (root) | `rci(body)` | High |
