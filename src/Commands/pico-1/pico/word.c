#if	!defined(lint) && !defined(DOS)
static char rcsid[] = "$Id: word.c,v 4.41 2002/11/18 21:33:04 jpf Exp $";
#endif
/*
 * Program:	Word at a time routines
 *
 *
 * Michael Seibel
 * Networks and Distributed Computing
 * Computing and Communications
 * University of Washington
 * Administration Builiding, AG-44
 * Seattle, Washington, 98195, USA
 * Internet: mikes@cac.washington.edu
 *
 * Please address all bugs and comments to "pine-bugs@cac.washington.edu"
 *
 *
 * Pine and Pico are registered trademarks of the University of Washington.
 * No commercial use of these trademarks may be made without prior written
 * permission of the University of Washington.
 * 
 * Pine, Pico, and Pilot software and its included text are Copyright
 * 1989-2002 by the University of Washington.
 * 
 * The full text of our legal notices is contained in the file called
 * CPYRIGHT, included with this distribution.
 *
 */
/*
 * The routines in this file implement commands that work word at a time.
 * There are all sorts of word mode commands. If I do any sentence and/or
 * paragraph mode commands, they are likely to be put in this file.
 */

#include	"headers.h"


/* Word wrap on n-spaces. Back-over whatever precedes the point on the current
 * line and stop on the first word-break or the beginning of the line. If we
 * reach the beginning of the line, jump back to the end of the word and start
 * a new line.  Otherwise, break the line at the word-break, eat it, and jump
 * back to the end of the word.
 * Returns TRUE on success, FALSE on errors.
 */
wrapword()
{
    register int cnt;			/* size of word wrapped to next line */
    register int bp;			/* index to wrap on */
    register int first = -1;
    register int i;

    if(curwp->w_doto <= 0)		/* no line to wrap? */
      return(FALSE);

    for(bp = cnt = i = 0; cnt < llength(curwp->w_dotp) && !bp; cnt++, i++){
	if(isspace((unsigned char) lgetc(curwp->w_dotp, cnt).c)){
	    first = 0;
	    if(lgetc(curwp->w_dotp, cnt).c == TAB)
	      while(i+1 & 0x07)
		i++;
	}
	else if(!first)
	  first = cnt;

	if(first > 0 && i >= fillcol)
	  bp = first;
    }

    if(!bp)
      return(FALSE);

    /* bp now points to the first character of the next line */
    cnt = curwp->w_doto - bp;
    curwp->w_doto = bp;

    if(!lnewline())			/* break the line */
      return(FALSE);

    /*
     * if there's a line below, it doesn't start with whitespace 
     * and there's room for this line...
     */
    if(!(curbp->b_flag & BFWRAPOPEN)
       && lforw(curwp->w_dotp) != curbp->b_linep 
       && llength(lforw(curwp->w_dotp)) 
       && !isspace((unsigned char) lgetc(lforw(curwp->w_dotp), 0).c)
       && (llength(curwp->w_dotp) + llength(lforw(curwp->w_dotp)) < fillcol)){
	gotoeol(0, 1);			/* then pull text up from below */
	if(lgetc(curwp->w_dotp, curwp->w_doto - 1).c != ' ')
	  linsert(1, ' ');

	forwdel(0, 1);
	gotobol(0, 1);
    }

    curbp->b_flag &= ~BFWRAPOPEN;	/* don't open new line next wrap */
					/* restore dot (account for NL)  */
    if(cnt && !forwchar(0, cnt < 0 ? cnt-1 : cnt))
      return(FALSE);

    return(TRUE);
}


/*
 * Move the cursor backward by "n" words. All of the details of motion are
 * performed by the "backchar" and "forwchar" routines. Error if you try to
 * move beyond the buffers.
 */
backword(f, n)
    int f, n;
{
        if (n < 0)
                return (forwword(f, -n));
        if (backchar(FALSE, 1) == FALSE)
                return (FALSE);
        while (n--) {
                while (inword() == FALSE) {
                        if (backchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
                while (inword() != FALSE) {
                        if (backchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
        }
        return (forwchar(FALSE, 1));
}

/*
 * Move the cursor forward by the specified number of words. All of the motion
 * is done by "forwchar". Error if you try and move beyond the buffer's end.
 */
forwword(f, n)
    int f, n;
{
        if (n < 0)
                return (backword(f, -n));
        while (n--) {
#if	NFWORD
                while (inword() != FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
#endif
                while (inword() == FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
#if	NFWORD == 0
                while (inword() != FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
#endif
        }
	return(TRUE);
}

#ifdef	MAYBELATER
/*
 * Move the cursor forward by the specified number of words. As you move,
 * convert any characters to upper case. Error if you try and move beyond the
 * end of the buffer. Bound to "M-U".
 */
upperword(f, n)
{
        register int    c;
	CELL            ac;

	ac.a = 0;
	if (curbp->b_mode&MDVIEW)	/* don't allow this command if	*/
		return(rdonly());	/* we are in read only mode	*/
        if (n < 0)
                return (FALSE);
        while (n--) {
                while (inword() == FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
                while (inword() != FALSE) {
                        c = lgetc(curwp->w_dotp, curwp->w_doto).c;
                        if (c>='a' && c<='z') {
                                ac.c = (c -= 'a'-'A');
                                lputc(curwp->w_dotp, curwp->w_doto, ac);
                                lchange(WFHARD);
                        }
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
        }
        return (TRUE);
}

/*
 * Move the cursor forward by the specified number of words. As you move
 * convert characters to lower case. Error if you try and move over the end of
 * the buffer. Bound to "M-L".
 */
lowerword(f, n)
{
        register int    c;
	CELL            ac;

	ac.a = 0;
	if (curbp->b_mode&MDVIEW)	/* don't allow this command if	*/
		return(rdonly());	/* we are in read only mode	*/
        if (n < 0)
                return (FALSE);
        while (n--) {
                while (inword() == FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
                while (inword() != FALSE) {
                        c = lgetc(curwp->w_dotp, curwp->w_doto).c;
                        if (c>='A' && c<='Z') {
                                ac.c (c += 'a'-'A');
                                lputc(curwp->w_dotp, curwp->w_doto, ac);
                                lchange(WFHARD);
                        }
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
        }
        return (TRUE);
}

/*
 * Move the cursor forward by the specified number of words. As you move
 * convert the first character of the word to upper case, and subsequent
 * characters to lower case. Error if you try and move past the end of the
 * buffer. Bound to "M-C".
 */
capword(f, n)
{
        register int    c;
	CELL	        ac;

	ac.a = 0;
	if (curbp->b_mode&MDVIEW)	/* don't allow this command if	*/
		return(rdonly());	/* we are in read only mode	*/
        if (n < 0)
                return (FALSE);
        while (n--) {
                while (inword() == FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                }
                if (inword() != FALSE) {
                        c = lgetc(curwp->w_dotp, curwp->w_doto).c;
                        if (c>='a' && c<='z') {
			    ac.c = (c -= 'a'-'A');
			    lputc(curwp->w_dotp, curwp->w_doto, ac);
			    lchange(WFHARD);
                        }
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                        while (inword() != FALSE) {
                                c = lgetc(curwp->w_dotp, curwp->w_doto).c;
                                if (c>='A' && c<='Z') {
				    ac.c = (c += 'a'-'A');
				    lputc(curwp->w_dotp, curwp->w_doto, ac);
				    lchange(WFHARD);
                                }
                                if (forwchar(FALSE, 1) == FALSE)
                                        return (FALSE);
                        }
                }
        }
        return (TRUE);
}

/*
 * Kill forward by "n" words. Remember the location of dot. Move forward by
 * the right number of words. Put dot back where it was and issue the kill
 * command for the right number of characters. Bound to "M-D".
 */
delfword(f, n)
{
        register long   size;
        register LINE   *dotp;
        register int    doto;

	if (curbp->b_mode&MDVIEW)	/* don't allow this command if	*/
		return(rdonly());	/* we are in read only mode	*/
        if (n < 0)
                return (FALSE);
        dotp = curwp->w_dotp;
        doto = curwp->w_doto;
        size = 0L;
        while (n--) {
#if	NFWORD
		while (inword() != FALSE) {
			if (forwchar(FALSE,1) == FALSE)
				return(FALSE);
			++size;
		}
#endif
                while (inword() == FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                        ++size;
                }
#if	NFWORD == 0
                while (inword() != FALSE) {
                        if (forwchar(FALSE, 1) == FALSE)
                                return (FALSE);
                        ++size;
                }
#endif
        }
        curwp->w_dotp = dotp;
        curwp->w_doto = doto;
        return (ldelete(size, kinsert));
}

/*
 * Kill backwards by "n" words. Move backwards by the desired number of words,
 * counting the characters. When dot is finally moved to its resting place,
 * fire off the kill command. Bound to "M-Rubout" and to "M-Backspace".
 */
delbword(f, n)
{
        register long   size;

	if (curbp->b_mode&MDVIEW)	/* don't allow this command if	*/
		return(rdonly());	/* we are in read only mode	*/
        if (n < 0)
                return (FALSE);
        if (backchar(FALSE, 1) == FALSE)
                return (FALSE);
        size = 0L;
        while (n--) {
                while (inword() == FALSE) {
                        if (backchar(FALSE, 1) == FALSE)
                                return (FALSE);
                        ++size;
                }
                while (inword() != FALSE) {
                        if (backchar(FALSE, 1) == FALSE)
                                return (FALSE);
                        ++size;
                }
        }
        if (forwchar(FALSE, 1) == FALSE)
                return (FALSE);
        return (ldelete(size, kinsert));
}
#endif	/* MAYBELATER */

/*
 * Return TRUE if the character at dot is a character that is considered to be
 * part of a word. The word character list is hard coded. Should be setable.
 */
inword()
{
    return(curwp->w_doto < llength(curwp->w_dotp)
	   && isalnum((unsigned char)lgetc(curwp->w_dotp, curwp->w_doto).c));
}

/*
 * Try to determine what the quote string for given line l is,
 * and put it into buf.
 *
 * Returns: 1 or the total number of indentations
 */
quote_match_work(q, l, buf, buflen)
    char *q;
    LINE *l;
    char *buf;
    int   buflen;
{
    register int i, n = 1, j, qb;
    int qstart, qend, k;

    /* 
     * The method for determining the quote string is:
     * 1) strip leading and trailing whitespace from q
     * 2) add all leading whitespace to buf
     * 3) check for q
     * 4) if q, append q to buf and any trailing whitespace
     * 5) repeat steps 3 and 4 as necessary
     * 
     * q in the future could be made to be an array of (char *)'s
     *    (">" and whatever the user's quote_string is)
     */

    /* count leading whitespace as part of the quote */
    *buf = '\0';
    for(j = 0; 
	(j <= llength(l))
	  && ((unsigned char) lgetc(l, j).c == ' ')
	  && j+1 < buflen; j++){
	buf[j] = lgetc(l, j).c;
	n = 1;
    }
    buf[j] = '\0';
    if(*q == '\0')
      return(1);

    /* pare down q so it contains no leading or trailing whitespace */
    qstart = 0;
    for(i = 0; (unsigned char)q[i] == ' '; i++)
      qstart = i + 1;
    qend = strlen(q);
    for(i = strlen(q); i > 0 && ((unsigned char)q[i-1] == ' '); i--)
      qend = i - 1;
    if(qend <= qstart)
      return(1);

    while(j <= llength(l)){
	for(i = qstart; (j <= llength(l)) && i < qend; i++, j++)
	  if(q[i] != lgetc(l, j).c)
	    return(n);

	n++;
	if(i >= qend){
	    if(strlen(buf) + qend - qstart < (buflen - 1))
	      strncat(buf, q + qstart, qend - qstart);
	}

	/* 
	 * if we're this far along, we've matched a quote string,
	 * and should now remove the following white space.
	 */
	for(k = strlen(buf);
	    (j <= llength(l))
	      && ((unsigned char)lgetc(l,j).c == ' ')
	      && (k + 1 < buflen);
	    j++, k++){
	    buf[k] = lgetc(l,j).c;
	}
	buf[k] = '\0';

	if(j > llength(l))
	  return(n);
    }
    return(n);  /* never reached */
}


/*
 * Return number of quotes if whatever starts the line matches the quote string
 *
 * The quote string returned in buf is now more lenient in what it returns, and now
 * handles leading white space and any numbers of q indentations.
 */
quote_match(q, l, buf, buflen)
    char *q;
    LINE *l;
    char *buf;
    int   buflen;
{
    int rv = 0;
    char nbuf[NLINE], pbuf[NLINE];

    rv = quote_match_work(q, l, buf, buflen);
    /*
     * Check to see if the next line is part of the same paragraph,
     * but don't count white space as a quote if that white space
     * is just a paragraph indentation.
     */
    if(lforw(l) != curbp->b_linep
       && quote_match_work(q, lforw(l), nbuf, NLINE) == rv
       && strlen(nbuf) < strlen(buf)
       && strncmp(buf, nbuf, strlen(nbuf)) == 0
       && llength(lforw(l)) > strlen(nbuf)){
	/*
	 * If we get here, we know that the next line has the same indent string
	 * that the current line, but it is padded with less spaces. This is
	 * the typical situation that we find at the beginning of a paragraph.
	 * We need to check, however, that this is so, by checking the previous
	 * line.
	 */
	if((l == curbp->b_linep)
	   || (rv != quote_match_work(q, lback(l), pbuf, NLINE))
	   || (strlen(pbuf) != strlen(buf))
	   || (strncmp(buf, pbuf, strlen(pbuf))))
	  strcpy(buf,nbuf);
    }

    return(rv);
}


fillpara(f, n)	/* Fill the current paragraph according to the current
		   fill column						*/

int f, n;	/* deFault flag and Numeric argument */

{
    int	    i, j, c, qlen, word[NSTRING], same_word,
	    spaces, word_len, line_len, line_last, qn;
    char   *qstr, qstr2[NSTRING];
    LINE   *eopline;
    REGION  region;

    if(curbp->b_mode&MDVIEW){		/* don't allow this command if	*/
	return(rdonly());		/* we are in read only mode	*/
    }
    else if (fillcol == 0) {		/* no fill column set */
	mlwrite("No fill column set", NULL);
	return(FALSE);
    }
    else if(curwp->w_dotp == curbp->b_linep) /* don't wrap! */
      return(FALSE);

    /* record the pointer to the line just past the EOP */
    if(gotoeop(FALSE, 1) == FALSE)
      return(FALSE);

    eopline = curwp->w_dotp;		/* first line of para */

    /* and back to the beginning of the paragraph */
    gotobop(FALSE, 1);

    /* determine if we're justifying quoted text or not */
    qstr = (Pmaster && Pmaster->quote_str
	    && quote_match(Pmaster->quote_str, curwp->w_dotp, qstr2, NSTRING)
	    && *qstr2) ? qstr2 : NULL;
    qlen = qstr ? strlen(qstr) : 0;

    /* let yank() know that it may be restoring a paragraph */
    thisflag |= CFFILL;

    if(!Pmaster)
      sgarbk = TRUE;
    
    curwp->w_flag |= WFMODE;

    /* cut the paragraph into our fill buffer */
    fdelete();
    curwp->w_doto = 0;
    getregion(&region, eopline, llength(eopline));
    if(!ldelete(region.r_size, finsert))
      return(FALSE);

    /* Now insert it back wrapped */
    spaces = word_len = line_len = same_word = 0;

    /* Beginning with leading quoting... */
    if(qstr){
	while(qstr[line_len])
	  linsert(1, qstr[line_len++]);

	line_last = ' ';			/* no word-flush space! */
    }

    /* ...and leading white space */
    for(i = qlen; (c = fremove(i)) == ' ' || c == TAB; i++){
	linsert(1, line_last = c);
	line_len += ((c == TAB) ? (~line_len & 0x07) + 1 : 1);
    }

    /* then digest the rest... */
    while((c = fremove(i++)) > 0){
	switch(c){
	  case '\n' :
	    i += qlen;				/* skip next quote string */

	  case TAB :
	  case ' ' :
	    spaces++;
	    same_word = 0;
	    break;

	  default :
	    if(spaces){				/* flush word? */
		if((line_len - qlen > 0)
		   && line_len + word_len + 1 > fillcol
		   && (line_len = fpnewline(qstr)))
		  line_last = ' ';	/* no word-flush space! */

		if(word_len){			/* word to write? */
		    if(line_len && !isspace((unsigned char) line_last)){
			linsert(1, ' ');	/* need padding? */
			line_len++;
		    }

		    line_len += word_len;
		    for(j = 0; j < word_len; j++)
		      linsert(1, line_last = word[j]);

		    if(spaces > 1 && strchr(".?!:;\")", line_last)){
			linsert(2, line_last = ' ');
			line_len += 2;
		    }

		    word_len = 0;
		}

		spaces = 0;
	    }

	    if(word_len + 1 >= NSTRING){
		/* Magic!  Fake that we output a wrapped word */
		if((line_len - qlen > 0) && !same_word++)
		  line_len = fpnewline(qstr);

		line_len += word_len;
		for(j = 0; j < word_len; j++)
		  linsert(1, word[j]);

		word_len  = 0;
		line_last = ' ';
	    }

	    word[word_len++] = c;
	    break;
	}
    }

    if(word_len){
	if((line_len - qlen > 0) && (line_len + word_len + 1 > fillcol))
	  (void) fpnewline(qstr);
	else if(line_len && !isspace((unsigned char) line_last))
	  linsert(1, ' ');

	for(j = 0; j < word_len; j++)
	  linsert(1, word[j]);
    }

    /* Leave cursor on first char of first line after paragraph */
    curwp->w_dotp = lforw(curwp->w_dotp);
    curwp->w_doto = 0;

    return(TRUE);
}


/*
 * fpnewline - output a fill paragraph newline mindful of quote string
 */
fpnewline(quote)
char *quote;
{
    int len;

    lnewline();
    for(len = 0; quote && *quote; quote++, len++)
      linsert(1, *quote);

    return(len);
}
