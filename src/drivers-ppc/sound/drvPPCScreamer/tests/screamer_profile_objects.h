/* Pismo live DT, BootROM 4.1.8f5. Provenance in SOURCES.md. */
static const char * const pismoObjects[]={
    "feature index 0 model Proj10PowerControl" ,
    "detect bit-mask 1 bit-match 1 device 2 index 0 model InSenseBitsDetect" ,
    "detect bit-mask 4 bit-match 4 device 16 index 1 model InSenseBitsDetect" ,
    "detect bit-mask 8 bit-match 0 device 32 index 2 model InSenseBitsDetect" ,
    "input icon-id -16526 index 1 name-id -20520  port-connection 2 port-type 0x656D6963 zero-gain 0 model ExternalMic" ,
    "input icon-id -16526 index 2 name-id -20528 port-connection 2 port-type 0x73696E6A zero-gain 0 model InputPort" ,
    "input icon-id -20184 index 4 name-id -20530 port-connection 4 port-type 0x70636D20 zero-gain 0 model NoRecordInput" ,
    "input index 5 model NoInput" ,
    "output device-mask 2 device-match 0 icon-id -16563 index 0 name-id -20525 port-connection 2 port-type 0x6973706B model OutputPort" ,
    "output device-mask 2 device-match 2 icon-id -16563 index 1 name-id -20524 port-connection 1 port-type 0x6864706E model OutputPort" ,
    "mux model MuxProgOut source-map-count 2 source-map 696D696300000002000000006D6F646D0000000200000002" ,
    "input icon-id -16525 index 0 name-id -20532 port-connection 1 port-type 0x696D6963 zero-gain 0x00138000 model IntMicMuxedInput" ,
    "input icon-id -20184 index 3 name-id -20540 port-connection 1 port-type 0x6D6F646D zero-gain 0x00000000 model MuxedInput" ,
    "" ,
    "" ,
    0
};

/* Routing facts from kiheis-sound in Apple iMac 4.1.9f1 firmware;
 * model-dependent speaker param is added by the test. Not a live DT dump. */
static const char * const imacObjects[]={
    "init operation 2 param 00000001 param-size 4" ,
    "feature index 0 model Proj7PowerControl" ,
    "feature index 2 model PhaseInversion port-channels 2" ,
    "detect bit-mask 6 device 2 index 0 model AnyInSenseBitsDetect" ,
    "detect bit-mask 14 bit-match 0 device 1 index 1 model InSenseBitsDetect" ,
    "detect bit-mask 14 bit-match 8 device 4 index 2 model InSenseBitsDetect" ,
    "detect bit-mask 1 bit-match 1 device 16 index 3 model InSenseBitsDetect" ,
    "input port-connection 1 port-type 0x696D6963 port-channels 1 model MonoMic" ,
    "input port-connection 2 port-type 0x656D6963 model ExternalMic" ,
    "input port-connection 2 port-type 0x73696E6A model InputPort" ,
    "input port-connection 3 port-type 0x6d6f646d model InputPort" ,
    "input index 4 model NoInput" ,
    "output device-mask 6 device-match 4 port-connection 1 port-type 0x6573706B model OutputPort" ,
    "output device-mask 3 device-match 3 port-connection 2 port-type 0x6973706B param 0 model Proj5Speaker" ,
    0
};
