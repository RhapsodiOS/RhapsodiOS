#ifndef RBUILD_PRODUCTS_H
#define RBUILD_PRODUCTS_H
/* Validate code by contents. Object collections permit paired CPU buckets.
 * Dependencies may contain a superset; newly built products must match exactly. */
int products_validate(const char *root, unsigned required,
                      int object_collection, int allow_superset);
#endif
