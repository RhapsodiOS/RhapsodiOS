#ifndef _PEXPERT_KEYLARGO_MODEL_H_
#define _PEXPERT_KEYLARGO_MODEL_H_

static int
PEKeyLargoIsCore99Model(const char *model)
{
    static const char *models[] = { "PowerMac2,1", "PowerMac2,2",
        "PowerMac3,1", "PowerMac3,2", "PowerMac3,3", "PowerMac4,1",
        "PowerMac5,1", "PowerBook2,1", "PowerBook3,1" };
    unsigned int i,j;

    if (model == 0)
        return 0;
    for (i = 0; i < sizeof(models) / sizeof(models[0]); ++i) {
        for (j = 0; models[i][j] && model[j] == models[i][j]; ++j)
            ;
        if (model[j] == '\0' && models[i][j] == '\0')
            return 1;
    }
    return 0;
}

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
