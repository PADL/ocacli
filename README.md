ocacli
======

`ocacli` is a AES70/OCA command-line client.

```bash
% ocacli -h localhost -p 65000
/> help
  cd                    Change current object path
  clear-cache           Clear object cache
  clear-flag            Clear a flag
  connect               Connect to device
  connection-info       Display connection status
  device-info           Show device information
  disconnect            Disconnect from device
  dump                  Recursively display JSON-formatted object
  exit                  Exit the OCA CLI
  flags                 Show enabled flags
  get                   Retrieve a property
  help                  Display this help command
  list                  Lists action objects in block
  lock                  Lock object from writes
  lock-total            Lock object from reads and writes
  popd                  Remove object from stack
  pushd                 Add current path to top of stack
  pwd                   Print current object path
  resolve               Resolves an object number to a name
  set                   Set a property
  set-flag              Enable a flag
  show                  Show object properties
  statistics            Show connection statistics
  subscribe             Add a property event subscription
  unlock                Unlock object
  unsubscribe           Remove a property event subscription
  up                    Change to parent object path
  watch                 Monitor property events
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
