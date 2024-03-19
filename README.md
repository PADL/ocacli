ocacli
======

`ocacli` is a AES70/OCA command-line client.

```bash
% ocacli -h localhost -p 65000
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
