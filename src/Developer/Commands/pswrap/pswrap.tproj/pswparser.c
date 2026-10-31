#include <sys/cdefs.h>
#ifndef lint
#if 0
static char yysccsid[] = "@(#)yaccpar	1.9 (Berkeley) 02/21/93";
#else
__IDSTRING(yyrcsid, "$NetBSD: skeleton.c,v 1.14 1997/10/20 03:41:16 lukem Exp $");
#endif
#endif
#include <stdlib.h>
#define YYBYACC 1
#define YYMAJOR 1
#define YYMINOR 9
#define YYLEX yylex()
#define YYEMPTY -1
#define yyclearin (yychar=(YYEMPTY))
#define yyerrok (yyerrflag=0)
#define YYRECOVERING (yyerrflag!=0)
#define YYPREFIX "yy"
#line 21 "pswparser.y"

#include "pswpriv.h"
#include "pswsemantics.h"

#line 29 "pswparser.y"
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
#line 36 "y.tab.c"
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
#define YYERRCODE 256
short yylhs[] = {                                        -1,
    0,    0,   15,   15,    3,    3,    2,    2,    6,    6,
    6,    6,    7,    7,    7,   16,   16,    9,    9,    9,
   11,   10,   12,   12,   12,   12,   12,   13,    4,    4,
    4,    4,    4,    4,    5,    5,    5,    5,    5,   14,
   14,    8,    8,    8,    8,    8,    8,    8,    8,    8,
    8,    8,    8,    8,    8,    8,    8,    8,    8,    8,
    8,    8,    8,    1,    1,    1,    1,    1,    1,    1,
    1,    1,    1,
};
short yylen[] = {                                         2,
    0,    2,    3,    2,    0,    1,    1,    2,    2,    3,
    5,    4,    3,    4,    3,    0,    1,    2,    1,    3,
    2,    2,    1,    3,    2,    3,    3,    2,    1,    3,
    1,    2,    3,    3,    2,    4,    6,    6,    1,    1,
    1,    1,    1,    1,    1,    2,    1,    2,    1,    2,
    1,    1,    2,    2,    3,    2,    3,    1,    1,    2,
    2,    2,    2,    1,    1,    1,    1,    1,    1,    1,
    2,    3,    3,
};
short yydefred[] = {                                      1,
    0,    0,    0,    0,    0,    2,    4,    0,    0,    0,
   69,   70,   65,   66,   67,   68,   64,    0,    0,    0,
    7,    0,    0,    0,   42,    0,   44,    0,    0,    0,
    0,   45,   58,   59,    9,    0,    0,    0,   19,    0,
    0,   23,   15,    0,   13,   71,    0,    0,    8,    3,
   21,   61,    0,    0,   54,   46,   50,   63,   48,   62,
   60,    0,   31,    0,    0,    0,   29,   10,    0,    0,
   18,    0,    0,   22,   14,   72,   73,   57,   55,   12,
    0,   35,    0,    0,    0,   20,   26,   27,   24,   40,
   41,    0,   33,   34,   30,   11,    0,    0,   37,   38,
};
short yydgoto[] = {                                       1,
   21,   22,   23,   66,   67,    4,    5,   37,   38,   39,
   40,   41,   42,   92,    6,   71,
};
short yysindex[] = {                                      0,
 -216, -249, -223,  -85,  -41,    0,    0,   -5, -254,    2,
    0,    0,    0,    0,    0,    0,    0, -262,  -85,  -85,
    0,  -85, -183, -189,    0, -182,    0, -214, -252, -233,
 -181,    0,    0,    0,    0, -196,  -40,  -33,    0,   31,
  -54,    0,    0,   52,    0,    0,    3,  -25,    0,    0,
    0,    0, -174, -169,    0,    0,    0,    0,    0,    0,
    0,   58,    0,   10, -168,  -43,    0,    0, -196, -196,
    0, -196, -206,    0,    0,    0,    0,    0,    0,    0,
 -195,    0,  -32,  -39,   63,    0,    0,    0,    0,    0,
    0,    9,    0,    0,    0,    0,   47, -193,    0,    0,
};
short yyrindex[] = {                                      0,
    0,    0,    0, -152,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,   18,  -13,
    0,  -86,    0,    0,    0,  -38,    0,  -26,  -22,  -21,
  -20,    0,    0,    0,    0,    0,    0,    0,    0,  -30,
  -30,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,  -19,  -18,    0,    0,    0,    0,    0,    0,
    0,    0,    0,  -16,    0,  -27,    0,    0,    0,  -29,
    0,  -10,  -29,    0,    0,    0,    0,    0,    0,    0,
    0,    0,  -15,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,  -14,    0,    0,    0,
};
short yygindex[] = {                                      0,
   85,    0,   61,    0,    1,    0,    0,    0,    0,  -23,
    0,    0,   14,    0,    0,   72,
};
#define YYTABLESIZE 253
short yytable[] = {                                      35,
   84,   65,   65,   43,   73,   19,    6,   68,    7,   65,
   16,   17,   62,   28,   57,   52,   44,   58,   46,   51,
   49,   47,   56,   53,   39,   32,   36,   39,   32,   36,
   25,   28,    8,   59,   43,    9,   60,   20,    6,    2,
    3,   45,   39,   32,   36,   85,   86,   10,   25,   88,
   53,   54,   55,   56,   25,   26,   27,   28,   29,   30,
   31,   32,   33,   34,   25,   26,   27,   28,   29,   30,
   31,   32,   33,   34,   50,   90,   91,   99,  100,   47,
   48,   51,   36,   93,   95,   87,   89,   52,   61,   70,
   69,   75,   78,   16,   17,   76,   28,   79,   80,   77,
   81,   97,   82,   96,   98,    5,   49,   39,   32,   36,
    5,    5,   74,   25,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    6,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,    0,    0,    0,    0,    0,   11,   12,   13,
   14,   15,   16,   17,   18,    0,    0,    0,    0,    0,
    0,   72,    0,    0,    0,    0,    0,    0,    0,    0,
    0,    0,   83,    0,    0,   63,   94,   43,   24,   25,
   26,   27,   28,   29,   30,   31,   32,   33,   34,   52,
   64,   64,   43,   51,   49,   47,   56,   53,   64,   39,
   32,   36,    0,    0,   52,   25,    0,    0,   51,   49,
   47,   56,   53,
};
short yycheck[] = {                                      41,
   44,   42,   42,   42,   59,   91,   93,   41,  258,   42,
   41,   41,   36,   41,  267,   42,  271,  270,  281,   42,
   42,   42,   42,   42,   41,   41,   41,   44,   44,   44,
   41,   59,  256,  267,   40,  259,  270,  123,  125,  256,
  257,   40,   59,   59,   59,   69,   70,  271,   59,  256,
  265,  266,  267,  268,  261,  262,  263,  264,  265,  266,
  267,  268,  269,  270,  261,  262,  263,  264,  265,  266,
  267,  268,  269,  270,  258,  271,  272,  271,  272,   19,
   20,  271,  124,   83,   84,   72,   73,  270,  270,   59,
  124,   40,  267,  124,  124,   93,  124,  267,   41,  125,
   91,   93,  271,   41,   58,  258,   22,  124,  124,  124,
   93,  125,   41,  124,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,  258,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,   -1,   -1,   -1,   -1,   -1,  273,  274,  275,
  276,  277,  278,  279,  280,   -1,   -1,   -1,   -1,   -1,
   -1,  256,   -1,   -1,   -1,   -1,   -1,   -1,   -1,   -1,
   -1,   -1,  256,   -1,   -1,  256,  256,  256,  260,  261,
  262,  263,  264,  265,  266,  267,  268,  269,  270,  256,
  271,  271,  271,  256,  256,  256,  256,  256,  271,  256,
  256,  256,   -1,   -1,  271,  256,   -1,   -1,  271,  271,
  271,  271,  271,
};
#define YYFINAL 1
#ifndef YYDEBUG
#define YYDEBUG 0
#endif
#define YYMAXTOKEN 281
#if YYDEBUG
char *yyname[] = {
"end-of-file",0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,"'('","')'","'*'",0,"','",0,0,0,0,0,0,0,0,0,0,0,0,0,"':'","';'",0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"'['",0,"']'",0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,"'{'","'|'","'}'",0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
0,0,0,0,0,"DEFINEPS","ENDPS","STATIC","PSCONTEXT","BOOLEAN","FLOAT","DOUBLE",
"UNSIGNED","SHORT","LONG","INT","CHAR","USEROBJECT","NUMSTRING","CNAME",
"CINTEGER","PSNAME","PSLITNAME","PSREAL","PSBOOLEAN","PSSTRING","PSHEXSTRING",
"PSINTEGER","PSSUBNAME","PSINDEX",
};
char *yyrule[] = {
"$accept : Module",
"Module :",
"Module : Module Definition",
"Definition : Header Body ENDPS",
"Definition : error ENDPS",
"Body :",
"Body : Tokens",
"Tokens : Token",
"Tokens : Tokens Token",
"Header : Def ')'",
"Header : Def InArgs ')'",
"Header : Def InArgs '|' Args ')'",
"Header : Def '|' Args ')'",
"Def : DEFINEPS CNAME '('",
"Def : DEFINEPS STATIC CNAME '('",
"Def : DEFINEPS error '('",
"Semi :",
"Semi : ';'",
"InArgs : ContextArg Semi",
"InArgs : Args",
"InArgs : ContextArg ';' Args",
"ContextArg : PSCONTEXT CNAME",
"Args : SubArgs Semi",
"SubArgs : Arg",
"SubArgs : SubArgs ';' Arg",
"SubArgs : SubArgs error",
"SubArgs : SubArgs error Arg",
"SubArgs : SubArgs ';' error",
"Arg : Type Items",
"Items : Item",
"Items : Items ',' Item",
"Items : error",
"Items : Items error",
"Items : Items error Item",
"Items : Items ',' error",
"Item : '*' CNAME",
"Item : CNAME '[' Subscript ']'",
"Item : CNAME '[' Subscript ']' ':' CNAME",
"Item : CNAME '[' Subscript ']' ':' CINTEGER",
"Item : CNAME",
"Subscript : CNAME",
"Subscript : CINTEGER",
"Type : BOOLEAN",
"Type : FLOAT",
"Type : DOUBLE",
"Type : CHAR",
"Type : UNSIGNED CHAR",
"Type : INT",
"Type : LONG INT",
"Type : LONG",
"Type : SHORT INT",
"Type : SHORT",
"Type : UNSIGNED",
"Type : UNSIGNED LONG",
"Type : UNSIGNED INT",
"Type : UNSIGNED LONG INT",
"Type : UNSIGNED SHORT",
"Type : UNSIGNED SHORT INT",
"Type : USEROBJECT",
"Type : NUMSTRING",
"Type : INT NUMSTRING",
"Type : FLOAT NUMSTRING",
"Type : LONG NUMSTRING",
"Type : SHORT NUMSTRING",
"Token : PSINTEGER",
"Token : PSREAL",
"Token : PSBOOLEAN",
"Token : PSSTRING",
"Token : PSHEXSTRING",
"Token : PSNAME",
"Token : PSLITNAME",
"Token : PSSUBNAME PSINDEX",
"Token : '[' Body ']'",
"Token : '{' Body '}'",
};
#endif
#ifdef YYSTACKSIZE
#undef YYMAXDEPTH
#define YYMAXDEPTH YYSTACKSIZE
#else
#ifdef YYMAXDEPTH
#define YYSTACKSIZE YYMAXDEPTH
#else
#define YYSTACKSIZE 10000
#define YYMAXDEPTH 10000
#endif
#endif
#define YYINITSTACKSIZE 200
int yydebug;
int yynerrs;
int yyerrflag;
int yychar;
short *yyssp;
YYSTYPE *yyvsp;
YYSTYPE yyval;
YYSTYPE yylval;
short *yyss;
short *yysslim;
YYSTYPE *yyvs;
int yystacksize;
/* allocate initial stack or double stack size, up to YYMAXDEPTH */
int yyparse __P((void));
static int yygrowstack __P((void));
static int yygrowstack()
{
    int newsize, i;
    short *newss;
    YYSTYPE *newvs;

    if ((newsize = yystacksize) == 0)
        newsize = YYINITSTACKSIZE;
    else if (newsize >= YYMAXDEPTH)
        return -1;
    else if ((newsize *= 2) > YYMAXDEPTH)
        newsize = YYMAXDEPTH;
    i = yyssp - yyss;
    if ((newss = (short *)realloc(yyss, newsize * sizeof *newss)) == NULL)
        return -1;
    yyss = newss;
    yyssp = newss + i;
    if ((newvs = (YYSTYPE *)realloc(yyvs, newsize * sizeof *newvs)) == NULL)
        return -1;
    yyvs = newvs;
    yyvsp = newvs + i;
    yystacksize = newsize;
    yysslim = yyss + newsize - 1;
    return 0;
}

#define YYABORT goto yyabort
#define YYREJECT goto yyabort
#define YYACCEPT goto yyaccept
#define YYERROR goto yyerrlab
int
yyparse()
{
    int yym, yyn, yystate;
#if YYDEBUG
    char *yys;

    if ((yys = getenv("YYDEBUG")) != NULL)
    {
        yyn = *yys;
        if (yyn >= '0' && yyn <= '9')
            yydebug = yyn - '0';
    }
#endif

    yynerrs = 0;
    yyerrflag = 0;
    yychar = (-1);

    if (yyss == NULL && yygrowstack()) goto yyoverflow;
    yyssp = yyss;
    yyvsp = yyvs;
    *yyssp = yystate = 0;

yyloop:
    if ((yyn = yydefred[yystate]) != 0) goto yyreduce;
    if (yychar < 0)
    {
        if ((yychar = yylex()) < 0) yychar = 0;
#if YYDEBUG
        if (yydebug)
        {
            yys = 0;
            if (yychar <= YYMAXTOKEN) yys = yyname[yychar];
            if (!yys) yys = "illegal-symbol";
            printf("%sdebug: state %d, reading %d (%s)\n",
                    YYPREFIX, yystate, yychar, yys);
        }
#endif
    }
    if ((yyn = yysindex[yystate]) && (yyn += yychar) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == yychar)
    {
#if YYDEBUG
        if (yydebug)
            printf("%sdebug: state %d, shifting to state %d\n",
                    YYPREFIX, yystate, yytable[yyn]);
#endif
        if (yyssp >= yysslim && yygrowstack())
        {
            goto yyoverflow;
        }
        *++yyssp = yystate = yytable[yyn];
        *++yyvsp = yylval;
        yychar = (-1);
        if (yyerrflag > 0)  --yyerrflag;
        goto yyloop;
    }
    if ((yyn = yyrindex[yystate]) && (yyn += yychar) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == yychar)
    {
        yyn = yytable[yyn];
        goto yyreduce;
    }
    if (yyerrflag) goto yyinrecovery;
    goto yynewerror;
yynewerror:
    yyerror("syntax error");
    goto yyerrlab;
yyerrlab:
    ++yynerrs;
yyinrecovery:
    if (yyerrflag < 3)
    {
        yyerrflag = 3;
        for (;;)
        {
            if ((yyn = yysindex[*yyssp]) && (yyn += YYERRCODE) >= 0 &&
                    yyn <= YYTABLESIZE && yycheck[yyn] == YYERRCODE)
            {
#if YYDEBUG
                if (yydebug)
                    printf("%sdebug: state %d, error recovery shifting\
 to state %d\n", YYPREFIX, *yyssp, yytable[yyn]);
#endif
                if (yyssp >= yysslim && yygrowstack())
                {
                    goto yyoverflow;
                }
                *++yyssp = yystate = yytable[yyn];
                *++yyvsp = yylval;
                goto yyloop;
            }
            else
            {
#if YYDEBUG
                if (yydebug)
                    printf("%sdebug: error recovery discarding state %d\n",
                            YYPREFIX, *yyssp);
#endif
                if (yyssp <= yyss) goto yyabort;
                --yyssp;
                --yyvsp;
            }
        }
    }
    else
    {
        if (yychar == 0) goto yyabort;
#if YYDEBUG
        if (yydebug)
        {
            yys = 0;
            if (yychar <= YYMAXTOKEN) yys = yyname[yychar];
            if (!yys) yys = "illegal-symbol";
            printf("%sdebug: state %d, error recovery discards token %d (%s)\n",
                    YYPREFIX, yystate, yychar, yys);
        }
#endif
        yychar = (-1);
        goto yyloop;
    }
yyreduce:
#if YYDEBUG
    if (yydebug)
        printf("%sdebug: state %d, reducing by rule %d (%s)\n",
                YYPREFIX, yystate, yyn, yyrule[yyn]);
#endif
    yym = yylen[yyn];
    yyval = yyvsp[1-yym];
    switch (yyn)
    {
case 3:
#line 72 "pswparser.y"
{ FinalizePSWrapDef(yyvsp[-2].header, yyvsp[-1].token); yyerrok; }
break;
case 4:
#line 74 "pswparser.y"
{ yyerrok; }
break;
case 5:
#line 79 "pswparser.y"
{ yyval.token = 0; }
break;
case 7:
#line 86 "pswparser.y"
{ yyval.token = AppendPSWToken(yyvsp[0].token, 0); }
break;
case 8:
#line 88 "pswparser.y"
{ yyval.token = AppendPSWToken(yyvsp[0].token, yyvsp[-1].token); yyerrok; }
break;
case 9:
#line 95 "pswparser.y"
{ yyval.header = PSWHeader(yyvsp[-1].flag, 0, 0); yyerrok; }
break;
case 10:
#line 97 "pswparser.y"
{ yyval.header = PSWHeader(yyvsp[-2].flag, yyvsp[-1].arg, 0); yyerrok; }
break;
case 11:
#line 99 "pswparser.y"
{ yyval.header = PSWHeader(yyvsp[-4].flag, yyvsp[-3].arg, yyvsp[-1].arg); yyerrok; }
break;
case 12:
#line 101 "pswparser.y"
{ yyval.header = PSWHeader(yyvsp[-3].flag, 0, yyvsp[-1].arg); yyerrok; }
break;
case 13:
#line 106 "pswparser.y"
{ PSWName(yyvsp[-1].object); yyval.flag = 0; yyerrok; }
break;
case 14:
#line 108 "pswparser.y"
{ PSWName(yyvsp[-1].object); yyval.flag = 1; yyerrok; }
break;
case 15:
#line 110 "pswparser.y"
{ PSWName("error"); yyval.flag = 0; yyerrok; }
break;
case 17:
#line 115 "pswparser.y"
{ yyerrok; }
break;
case 20:
#line 124 "pswparser.y"
{ yyval.arg = ConsPSWArgs(yyvsp[-2].arg, yyvsp[0].arg); }
break;
case 21:
#line 129 "pswparser.y"
{ yyval.arg = PSWArg(T_CONTEXT, PSWItem(yyvsp[0].object)); }
break;
case 24:
#line 141 "pswparser.y"
{ yyerrok; yyval.arg = AppendPSWArgs(yyvsp[0].arg, yyvsp[-2].arg); }
break;
case 26:
#line 144 "pswparser.y"
{ yyerrok; yyval.arg = AppendPSWArgs(yyvsp[0].arg, yyvsp[-2].arg); }
break;
case 28:
#line 149 "pswparser.y"
{ yyval.arg = PSWArg(yyvsp[-1].flag, yyvsp[0].item); yyerrok; }
break;
case 30:
#line 156 "pswparser.y"
{ yyerrok; yyval.item = AppendPSWItems(yyvsp[0].item, yyvsp[-2].item); }
break;
case 31:
#line 157 "pswparser.y"
{ yyval.item = 0; }
break;
case 33:
#line 160 "pswparser.y"
{ yyerrok; yyval.item = AppendPSWItems(yyvsp[0].item, yyvsp[-2].item); }
break;
case 35:
#line 166 "pswparser.y"
{ yyval.item = PSWStarItem(yyvsp[0].object); }
break;
case 36:
#line 168 "pswparser.y"
{ yyval.item = PSWSubscriptItem(yyvsp[-3].object, yyvsp[-1].subscript); }
break;
case 37:
#line 170 "pswparser.y"
{ yyval.item = PSWScaleItem(yyvsp[-5].object, yyvsp[-3].subscript, yyvsp[0].object, NULL); }
break;
case 38:
#line 172 "pswparser.y"
{ yyval.item = PSWScaleItem(yyvsp[-5].object, yyvsp[-3].subscript, NULL, yyvsp[0].intobj); }
break;
case 39:
#line 174 "pswparser.y"
{ yyval.item = PSWItem(yyvsp[0].object); }
break;
case 40:
#line 179 "pswparser.y"
{ yyval.subscript = PSWNameSubscript(yyvsp[0].object); }
break;
case 41:
#line 181 "pswparser.y"
{ yyval.subscript = PSWIntegerSubscript(yyvsp[0].intobj); }
break;
case 42:
#line 186 "pswparser.y"
{ yyval.flag = T_BOOLEAN; }
break;
case 43:
#line 188 "pswparser.y"
{ yyval.flag = T_FLOAT; }
break;
case 44:
#line 190 "pswparser.y"
{ yyval.flag = T_DOUBLE; }
break;
case 45:
#line 192 "pswparser.y"
{ yyval.flag = T_CHAR; }
break;
case 46:
#line 194 "pswparser.y"
{ yyval.flag = T_UCHAR; }
break;
case 47:
#line 196 "pswparser.y"
{ yyval.flag = T_INT; }
break;
case 48:
#line 198 "pswparser.y"
{ yyval.flag = T_LONGINT; }
break;
case 49:
#line 200 "pswparser.y"
{ yyval.flag = T_LONGINT; }
break;
case 50:
#line 202 "pswparser.y"
{ yyval.flag = T_SHORTINT; }
break;
case 51:
#line 204 "pswparser.y"
{ yyval.flag = T_SHORTINT; }
break;
case 52:
#line 206 "pswparser.y"
{ yyval.flag = T_UINT; }
break;
case 53:
#line 208 "pswparser.y"
{ yyval.flag = T_ULONGINT; }
break;
case 54:
#line 210 "pswparser.y"
{ yyval.flag = T_UINT; }
break;
case 55:
#line 212 "pswparser.y"
{ yyval.flag = T_ULONGINT; }
break;
case 56:
#line 214 "pswparser.y"
{ yyval.flag = T_USHORTINT; }
break;
case 57:
#line 216 "pswparser.y"
{ yyval.flag = T_USHORTINT; }
break;
case 58:
#line 218 "pswparser.y"
{ yyval.flag = T_USEROBJECT; }
break;
case 59:
#line 220 "pswparser.y"
{ yyval.flag = T_NUMSTR; }
break;
case 60:
#line 222 "pswparser.y"
{ yyval.flag = T_NUMSTR; }
break;
case 61:
#line 224 "pswparser.y"
{ yyval.flag = T_FLOATNUMSTR; }
break;
case 62:
#line 226 "pswparser.y"
{ yyval.flag = T_LONGNUMSTR; }
break;
case 63:
#line 228 "pswparser.y"
{ yyval.flag = T_SHORTNUMSTR; }
break;
case 64:
#line 233 "pswparser.y"
{ yyval.token = PSWToken(T_INT, yyvsp[0].intobj); }
break;
case 65:
#line 235 "pswparser.y"
{ yyval.token = PSWToken(T_FLOAT, yyvsp[0].object); }
break;
case 66:
#line 237 "pswparser.y"
{ yyval.token = PSWToken(T_BOOLEAN, yyvsp[0].object); }
break;
case 67:
#line 239 "pswparser.y"
{ yyval.token = PSWToken(T_STRING, yyvsp[0].object); }
break;
case 68:
#line 241 "pswparser.y"
{ yyval.token = PSWToken(T_HEXSTRING, yyvsp[0].object); }
break;
case 69:
#line 243 "pswparser.y"
{ yyval.token = PSWToken(T_NAME, yyvsp[0].object); }
break;
case 70:
#line 245 "pswparser.y"
{ yyval.token = PSWToken(T_LITNAME, yyvsp[0].object); }
break;
case 71:
#line 247 "pswparser.y"
{ yyval.token = PSWToken2(T_SUBSCRIPTED, yyvsp[-1].object, yyvsp[0].object); }
break;
case 72:
#line 249 "pswparser.y"
{ yyval.token = PSWToken(T_ARRAY, yyvsp[-1].token); }
break;
case 73:
#line 251 "pswparser.y"
{ yyval.token = PSWToken(T_PROC, yyvsp[-1].token); }
break;
#line 709 "y.tab.c"
    }
    yyssp -= yym;
    yystate = *yyssp;
    yyvsp -= yym;
    yym = yylhs[yyn];
    if (yystate == 0 && yym == 0)
    {
#if YYDEBUG
        if (yydebug)
            printf("%sdebug: after reduction, shifting from state 0 to\
 state %d\n", YYPREFIX, YYFINAL);
#endif
        yystate = YYFINAL;
        *++yyssp = YYFINAL;
        *++yyvsp = yyval;
        if (yychar < 0)
        {
            if ((yychar = yylex()) < 0) yychar = 0;
#if YYDEBUG
            if (yydebug)
            {
                yys = 0;
                if (yychar <= YYMAXTOKEN) yys = yyname[yychar];
                if (!yys) yys = "illegal-symbol";
                printf("%sdebug: state %d, reading %d (%s)\n",
                        YYPREFIX, YYFINAL, yychar, yys);
            }
#endif
        }
        if (yychar == 0) goto yyaccept;
        goto yyloop;
    }
    if ((yyn = yygindex[yym]) && (yyn += yystate) >= 0 &&
            yyn <= YYTABLESIZE && yycheck[yyn] == yystate)
        yystate = yytable[yyn];
    else
        yystate = yydgoto[yym];
#if YYDEBUG
    if (yydebug)
        printf("%sdebug: after reduction, shifting from state %d \
to state %d\n", YYPREFIX, *yyssp, yystate);
#endif
    if (yyssp >= yysslim && yygrowstack())
    {
        goto yyoverflow;
    }
    *++yyssp = yystate;
    *++yyvsp = yyval;
    goto yyloop;
yyoverflow:
    yyerror("yacc stack overflow");
yyabort:
    return (1);
yyaccept:
    return (0);
}
