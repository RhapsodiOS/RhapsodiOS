#ifndef _PEXPERT_KEYLARGO_MODEL_H_
#define _PEXPERT_KEYLARGO_MODEL_H_

static int
PEKeyLargoUsesLegacyMacIOSpan(const char *model)
{
    static const char legacyModel[] = "PowerMac3,1";
    unsigned int index;

    if (model == 0)
        return 0;
    for (index = 0; legacyModel[index] != '\0'; index++) {
        if (model[index] != legacyModel[index])
            return 0;
    }
    return model[index] == '\0';
}

#endif /* _PEXPERT_KEYLARGO_MODEL_H_ */
