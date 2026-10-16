# Foundation `NSThread(NSConnectionWorkQueue)` owner correction

The conversation tracking and work-queue methods already existed in
`NSThread.m`, but were defined inside the flat `NSThread` implementation. The
NSConnection ABI manifest assigns `lastConversation`, `addConversation:`,
`removeConversation`, `clearConversationRequest`, `conversationRequest`,
`setConversationRequest:`, `workQueue`, and `+mapConversationToThread:` to
`NSThread(NSConnectionWorkQueue)`.

Moved those existing method bodies to the exact ABI category without changing
their behavior. Static exact-owner and whitespace checks only; no tests or
builds were run.
