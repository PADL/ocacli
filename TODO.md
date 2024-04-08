## General

* support ../.., ../., etc paths
* Tree / graph display
* domain socket support
* ctrl-C in watch view shouldn't exit program
* add back cyclic ref check in getRecursiveFallback()
* fix reconnect bug (issue #2)
* test autoreconnect

## Commands to implement

* OcaBlock
    - apply-param-set
    - store-current-param-set
    - find
    - find-recursive
* OcaDeviceManager
    - apply-patch
    - set-reset-key
    - clear-reset-cause
* OcaFirmwareManager
    - update, update-active
    - update-passive
* OcaLibraryManager
    - add-library
    - delete-library
    - get-library-count
    - get-library-list
* OcaDeviceTimeManager
    - set-ptp-time
* OcaDiagnosticManager
    - get-lock-status
* OcaLockManager
    - lock-wait
    - abort-waits
* OcaApplicationNetwork
    - control
* OcaMediaTransportNetwork
    - set-port-name etc
    - delete-connector
    - set-connector
    - set-sink-connector
    - set-source-connector
    - control-connector
    - add-sink
    - add-source
    - get-connector-status
