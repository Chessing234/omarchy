#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

assert(
  /property int fingerprintRetryAttempt: 0/.test(serviceQml),
  'lock tracks fingerprint retry attempts per lock session'
)

assert(
  /readonly property int fingerprintRetryMax: 8/.test(serviceQml),
  'fingerprint retries are capped per lock session'
)

assert(
  /function scheduleFingerprintRetry\(\)/.test(serviceQml),
  'fingerprint failures go through a backoff scheduler'
)

assert(
  /fingerprintRetryBaseMs \* Math\.pow\(2, fingerprintRetryAttempt\)/.test(serviceQml),
  'fingerprint retry delay grows exponentially'
)

assert(
  /fingerprintRetryAttempt >= fingerprintRetryMax/.test(serviceQml),
  'fingerprint retries stop after the cap instead of spinning forever'
)

const withoutScheduler = serviceQml.replace(/function scheduleFingerprintRetry\([\s\S]*?\n  \}\n/, '')
assert(
  !/else if \(fingerprintConfigured\) \{\s*fingerprintRetryTimer\.restart\(\)/.test(withoutScheduler),
  'failed fingerprint auth does not re-arm a fixed timer'
)
assert(
  !/if \(root\.lockRequested && root\.fingerprintConfigured\) fingerprintRetryTimer\.restart\(\)/.test(withoutScheduler),
  'fingerprint PAM errors do not re-arm a fixed timer'
)

assert(
  /root\.fingerprintRetryAttempt = 0/.test(serviceQml),
  'a newly secured lock resets the fingerprint retry counter'
)
JS
