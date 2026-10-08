"""The pre-installed image's fixed test password.

The hash is precomputed, because Python 3.13 has no crypt module: it is
crypt("rhapsodi", "rh"), traditional DES, from Git Bash's perl, and
Rhapsody's own crypt() gives the same string (checked on the build guest
with perl 5.004).  DES crypt reads only the first 8 characters.
"""
TEST_PASSWORD = "rhapsodi"
TEST_PASSWORD_HASH = "rhME8brSxdukA"
