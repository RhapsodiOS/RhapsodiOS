#ifndef RHAPSODIOS_AHCI_ATAPI_LOGIC_H
#define RHAPSODIOS_AHCI_ATAPI_LOGIC_H

#define AHCI_ATAPI_READ_16 0x88U

typedef struct {
    unsigned char peripheralType;
    unsigned char packetLength;
    int dmaDirSupported;
    char model[41];
    char serial[21];
    char firmware[9];
} AHCIATAPIIdentity;

unsigned int AHCIATAPIValidateCDBLength(unsigned char opcode,
                                         unsigned int suppliedLength,
                                         unsigned int cdbCapacity);
unsigned int AHCIATAPIPacketTimeout(int requestedSeconds);
int AHCIATAPITransportLength(unsigned int requestedBytes, int write,
                             unsigned int maximumBytes,
                             unsigned int *transportBytes);
unsigned int AHCIATAPIClipTransfer(unsigned int actualBytes,
                                    unsigned int requestedBytes);
int AHCIATAPIParseIdentity(const unsigned short words[256],
                           AHCIATAPIIdentity *identity);
int AHCIATAPIIdentityMatches(const AHCIATAPIIdentity *first,
                             const AHCIATAPIIdentity *second);
int AHCIATAPITranslateModeSense6(const unsigned char cdb6[6],
                                  unsigned int maxTransfer,
                                  unsigned char cdb10[12],
                                  unsigned int *translatedTransfer);
int AHCIATAPIRemapModeSense10(const unsigned char *atapiData,
                               unsigned int atapiBytes,
                               unsigned char *scsiData,
                               unsigned int scsiCapacity,
                               unsigned int *scsiBytes);
int AHCIATAPIEmulateModeSensePage2(const unsigned char cdb6[6],
                                    unsigned char *data,
                                    unsigned int capacity,
                                    unsigned int *actual);

#endif
