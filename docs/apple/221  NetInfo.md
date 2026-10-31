# 221  NetInfo

## Rhapsody Network Administration Model

- Marc Majka
- Rhapsody Core OS Team

## Administration = Information + Services

- Rhapsody supports several Information systems
  - NIS, DNS, LDAP, local files
- Primary Information system is NetInfo
- These systems just store data - various servers do the real work
- Today's presentation from the developer's point of view

## NetInfo Overview

- A reliable distributed data store for network and system administration
- Contains records describing users, printers, mailing lists, and etc.
- Also stores configuration settings, server and resource locations

## A Three-Level Hierarchy

- *Diagram: a domain tree with root `/`, children `foo` and `bar`, and grandchildren `ant`, `bat` (under `foo`) and `cat`, `dog` (under `bar`), each grandchild matching a host computer of the same name.*

## NetInfo Namespace

- A tree-structured namespace
- A hierarchy of domains
- Each domain stores a hierarchy of directories
- Directories are data bearing objects

## Domains and Directories

- *Diagram: the Domain Hierarchy (`/` with `foo` and `bar`); `bar` expands into its Directory Hierarchy: `/` with `groups`, `printers` and `users`, and `users` with `zippy` and `zorba`.*

## Property List

*The directory hierarchy (`/`, `groups`, `printers`, `users`, `zippy`, `zorba`), with the property list of `zorba`:*

- `name`: zorba
- `realname`: Zorba The Geek
- `passwd`: pg5nMizy/WeOs
- `uid`: 12345
- `gid`: 123
- `home`: /Users/zorba
- `shell`: /bin/csh
- `_writers_passwd`: zorba

## Storing Data

- A directory contains a list of properties
- Each property has one ASCII key and any number of ASCII values
- Directories in certain categories (e.g., users) have required properties
- New properties may be added on the fly

## Access Control

- NetInfo is world-readable
- All data is writable by "root" user
- Write ACLs per directory and per property

## Reliability

- Each domain has a master server
- A domain may have any number of clone servers
- Write operations always go to the master
- Several master/clone synchronization mechanisms
- Clients automatically reconnect in case of failure

## NetInfo Clients

- Most common lookups go through the System Library
- System Library uses `lookupd` to find things
- `lookupd` is the system's main NetInfo client
- Any program may be a NetInfo client

## System Look-up Path

- *Diagram: Application connects to the Rhapsody System Library, which connects to `lookupd`, which connects to NetInfo, DNS, NIS, others and Files.*

## lookupd

- System's "Information Clearinghouse"
- Client of NetInfo, NIS, DNS, etc.
- Cache for improved system performance
- When consulting NetInfo, climbs from local domain to root domain

## Talking to NetInfo

- Through System Libraries and `lookupd`
- Primitive ONC-RPC protocol
- "C" client library
- Objective-C API (NIAccess framework)
- Integrated directory services API planned

## System Libraries

- `gethostbyname()`, `getpwnam()`, and etc.
- Limited set of categories (users, printers, hosts, etc.)
- Limited set of properties for each category - no data for nonstandard keys in NetInfo

## ONC-RPC Protocol

- Tedious in the extreme
- No documentation

## C Client Library

- Fairly simple open, search, read, write-style routines
- Data Structures galore
- On-line documentation

## NIAccess Framework

- Objective-C API on top of C client library
- Classes for Domain, Directory, etc.
- On-line documentation

## What Can I Do with NetInfo?

- Create new network and system administration applications and management utilities
- Reliable data store
- Location broker and rendezvous for network applications
- Extend existing data to support your code (e.g., "security_clearance" property for a user)

## What Shouldn't I Do with NetInfo

- Poor performance on write operations
- Best performance for small (<= 512 byte) records
