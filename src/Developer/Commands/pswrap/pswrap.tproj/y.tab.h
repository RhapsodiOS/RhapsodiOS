#define DEFINEPS 257
#define ENDPS 258
#define STATIC 259
#define PSCONTEXT 260
#define BOOLEAN 261
#define FLOAT 262
#define DOUBLE 263
#define UNSIGNED 264
#define SHORT 265
#define LONG 266
#define INT 267
#define CHAR 268
#define USEROBJECT 269
#define NUMSTRING 270
#define CNAME 271
#define CINTEGER 272
#define PSNAME 273
#define PSLITNAME 274
#define PSREAL 275
#define PSBOOLEAN 276
#define PSSTRING 277
#define PSHEXSTRING 278
#define PSINTEGER 279
#define PSSUBNAME 280
#define PSINDEX 281
typedef union {
    char *object;
    int	intobj;
    Token token;
    Item item;
    Header header;
    int flag;
    Arg arg;
    Subscript subscript;
} YYSTYPE;
extern YYSTYPE yylval;
