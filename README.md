ocacli
======

`ocacli` is a AES70/OCA command-line client.

```bash
% ocacli -h localhost -p 65000
/> help
  add-signal-path                  Add a signal path to a block
  cd                               Change current object path
  clear-cache                      Clear object cache
  clear-flag                       Clear a flag
  connect                          Connect to device
  connection-info                  Display connection status
  construct-action-object          Construct action object using a factory
  delete-action-object             Delete block action object
  delete-input-clock-map-entry     Delete input port clock map entry
  delete-input-port                Delete input port
  delete-output-clock-map-entry    Delete output port clock map entry
  delete-output-port               Delete output port
  delete-signal-path               Delete a signal path to a block
  device-info                      Show device information
  disconnect                       Disconnect from device
  dump                             Recursively display JSON-formatted object
  dump-sparse-role-path-cache      Dump spare role path cache
  exit                             Exit the OCA CLI
  find                             Find action objects by role search string
  find-label-recursive             Recursively find action objects by label search string
  find-recursive                   Recursively find action objects by role search string
  get                              Retrieve a property
  get-flags                        Show enabled flags
  get-input-port-name              Get input port name
  get-output-port-name             Get output port name
  get-signal-path-recursive        Get recursive signal paths
  help                             Display this help command
  list                             Lists action objects in block
  list-object-numbers              Lists action objects in block by object number
  lock                             Lock object from writes
  lock-total                       Lock object from reads and writes
  popd                             Remove object from stack
  pushd                            Add current path to top of stack
  pwd                              Print current object path
  resolve                          Resolves an object number to a name
  set                              Set a property
  set-flag                         Enable a flag
  set-input-clock-map-entry        Set input port clock map entry
  set-input-port-name              Set input port name
  set-output-clock-map-entry       Set output port clock map entry
  set-output-port-name             Set output port name
  show                             Show object properties
  statistics                       Show connection statistics
  subscribe                        Add a property event subscription
  unlock                           Unlock object
  unsubscribe                      Remove a property event subscription
  up                               Change to parent object path
  watch                            Monitor property events
/> ls
Subscription Manager
Matrix
Block
Control Network
/> cd Block/Gain 
/Block/Gain> set label test 
/Block/Gain> set gain -24.3 
/Block/Gain> show 
classID: 1.1.1.5
classVersion: 2
enabled: true
gain: -24.3
label: test
latency: null
lockState: noLock
lockable: false
objectNumber: 4107
owner: 4098
portClockMap: [:]
ports: []
role: Gain
```
