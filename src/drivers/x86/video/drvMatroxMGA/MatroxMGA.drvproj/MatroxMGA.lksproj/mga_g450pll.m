/* $XFree86: xc/programs/Xserver/hw/xfree86/drivers/mga/mga_g450pll.c,v 1.2 2001/04/05 17:42:32 dawes Exp $ */
/*
 *
 * Mirko Viviani, mirko.viviani@gmail.com
 * Ported to NEXTSTEP 3.3 and up
 *
 */
/* All drivers should typically include these */
#include "driverkit/i386/ioPorts.h"
#include "xf86.h"
#include "xf86Priv.h"
#include "xf86_OSlib.h"
#include "xf86_HWlib.h"
#include "xf86cursor.h"
#include "vga.h"
#include "vgaPCI.h"

#include "mga_bios.h"
#include "mga_reg.h"
#include "mgax.h"

#import "MGA.h"

#define MNP_TABLE_SIZE 64
#define CLKSEL_MGA     0x0c
#define PLLLOCK        0x40


@implementation MatroxMGA (G450)


static CARD32 G450ApplyPFactor(CARD8 ucP, CARD32 *pulFIn)
{
   if(!(ucP & 0x40))
   {
      *pulFIn = *pulFIn / (2L << (ucP & 3));
   }

   return TRUE;
}


static CARD32 G450RemovePFactor(CARD8 ucP, CARD32 *pulFIn)
{
   if(!(ucP & 0x40))
   {
      *pulFIn = *pulFIn * (2L << (ucP & 3));
   }
  
   return TRUE; 
}


static CARD32 G450CalculVCO(CARD32 ulMNP, CARD32 *pulF)
{
   CARD8 ucM, ucN, ucP;

   ucM = (CARD8)((ulMNP >> 16) & 0xff);
   ucN = (CARD8)((ulMNP >>  8) & 0xff);
   ucP = (CARD8)(ulMNP & 0x03);

   *pulF = (27000 * (2 * (ucN + 2)) + ((ucM + 1) >> 1)) / (ucM + 1);
   
   return TRUE;
}


static CARD32 G450CalculDeltaFreq(CARD32 ulF1,
                                  CARD32 ulF2, CARD32 *pulDelta)
{
   if(ulF2 < ulF1)
   {
      *pulDelta = ((ulF1 - ulF2) * 1000) / ulF1;
   }
   else
   {
      *pulDelta = ((ulF2 - ulF1) * 1000) / ulF1;
   }
 
   return TRUE;
}




static CARD32 G450FindNextPLLParam(CARD32 ulFout,
                                   CARD32 *pulPLLMNP)
{
   CARD8 ucM, ucN, ucP, ucS;
   CARD32 ulVCO, ulVCOMin;

   ucM = (CARD8)((*pulPLLMNP >> 16) & 0xff);
   ucN = (CARD8)((*pulPLLMNP >>  8) & 0xff);
   ucP = (CARD8)(*pulPLLMNP &  0x43);

   ulVCOMin = 256000;

   if(ulVCOMin >= (255L * 8000))
   {
      ulVCOMin = 230000;
   }
   
   if((ucM == 9) && (ucP & 0x40))
   {
      *pulPLLMNP = 0xffffffff;
   } else if (ucM == 9)
   {
      if(ucP)
      {
         ucP--;
      }
      else
      {
         ucP = 0x40;
      }
      ucM = 0;
   }
   else
   {
      ucM++;
   }

   ulVCO = ulFout;

   G450RemovePFactor(ucP, &ulVCO);

   if(ulVCO < ulVCOMin)
   {
      *pulPLLMNP = 0xffffffff;
   }

   if(*pulPLLMNP != 0xffffffff)
   {
      ucN = (CARD8)(((ulVCO * (ucM+1) + 27000)/(27000 * 2)) - 2);

      ucS = 5;
      if(ulVCO < 1300000) ucS = 4;
      if(ulVCO < 1100000) ucS = 3;
      if(ulVCO <  900000) ucS = 2;
      if(ulVCO <  700000) ucS = 1;
      if(ulVCO <  550000) ucS = 0;

      ucP |= (CARD8)(ucS << 3);

      *pulPLLMNP &= 0xff000000;
      *pulPLLMNP |= (CARD32)ucM << 16;
      *pulPLLMNP |= (CARD32)ucN << 8;
      *pulPLLMNP |= (CARD32)ucP;
#ifdef DEBUG
      ErrorF("FINS_S: VCO = %d, S = %02X, *pulPLLMNP = %08X\n", ulVCO, (ULONG)ucS, *pulPLLMNP);
#endif
  }

   return TRUE;
}

 
static CARD32 G450FindFirstPLLParam(CARD32 ulFout, 
                                    CARD32 *pulPLLMNP)
{
   CARD8 ucP;
   CARD32 ulVCO;
   CARD32 ulVCOMax;

   /* Default value */
   ulVCOMax = 1300000;

   if(ulFout > (ulVCOMax/2))
   {
      ucP = 0x40;
      ulVCO = ulFout;
   }
   else
   {
      ucP = 3;
      ulVCO = ulFout;
      G450RemovePFactor(ucP, &ulVCO);
      while(ucP && (ulVCO > ulVCOMax))
      {
         ucP--;
         ulVCO = ulFout;
         G450RemovePFactor(ucP, &ulVCO);
      }
   }

   if(ulVCO > ulVCOMax)
   {
      *pulPLLMNP = 0xffffffff;
   }
   else
   {
      /* Pixel clock: 1 */
      *pulPLLMNP = (1 << 24) + 0xff0000 + ucP;
      G450FindNextPLLParam(ulFout, pulPLLMNP);
   }

   return TRUE;

}


- (void)G450WriteMNP:(CARD32)ulMNP
{
/*   MGAPtr pMga = MGAPTR(vga256InfoRec);
   MGARegPtr pReg;

   pReg = &pMga->ModeReg;

   if (!pMga->SecondCrtc) {
*/
      outMGAdac(MGAMMIOBase, MGA1064_PIX_PLLC_M, (CARD8)(ulMNP >> 16));   
      outMGAdac(MGAMMIOBase, MGA1064_PIX_PLLC_N, (CARD8)(ulMNP >>  8));   
      outMGAdac(MGAMMIOBase, MGA1064_PIX_PLLC_P, (CARD8) ulMNP);   
/*   } else {
      outMGAdac(MGA1064_VID_PLL_M, (CARD8)(ulMNP >> 16));
      outMGAdac(MGA1064_VID_PLL_N, (CARD8)(ulMNP >> 8)); 
      outMGAdac(MGA1064_VID_PLL_P, (CARD8) ulMNP);
   }*/
}


- (void)G450CompareMNP:(CARD32) ulFout MNP:(CARD32) ulMNP1
                   MNP2:(CARD32) ulMNP2 res:(long *)pulResult
{
   CARD32 ulFreq, ulDelta1, ulDelta2;

   G450CalculVCO(ulMNP1, &ulFreq);
   G450ApplyPFactor((CARD8) ulMNP1, &ulFreq);
   G450CalculDeltaFreq(ulFout, ulFreq, &ulDelta1);

   G450CalculVCO(ulMNP2, &ulFreq);
   G450ApplyPFactor((CARD8) ulMNP2, &ulFreq);
   G450CalculDeltaFreq(ulFout, ulFreq, &ulDelta2);

   if(ulDelta1 < ulDelta2)
   {
      *pulResult = -1;
   }
   else if(ulDelta1 > ulDelta2)
   {
      *pulResult = 1;
   }
   else
   {
      *pulResult = 0;
   }

   if((ulDelta1 <= 5) && (ulDelta2 <= 5))
   {
      if((ulMNP1 & 0xff0000) < (ulMNP2 & 0xff0000))
      {
         *pulResult = -1;
      }
      else if((ulMNP1 & 0xff0000) > (ulMNP2 & 0xff0000))
      {
         *pulResult = 1;
      }
   }
}


- (void)G450IsPllLocked: (BOOL *)lpbLocked
{
   CARD32 ulFallBackCounter, ulLockCount, ulCount;
   CARD8  ucPLLStatus;

   /* Pixel PLL */
//   if (!pMga->SecondCrtc)
      OUTREG8(0x3c00, 0x4f);    
/*   else
      OUTREG8(0x3c00, 0x8f);
*/

   ulFallBackCounter = 0;

   do 
   {
      ucPLLStatus = INREG8(0x3c0a);
      ulFallBackCounter++;
   } while(!(ucPLLStatus & PLLLOCK) && (ulFallBackCounter < 1000));

   ulLockCount = 0;
   if(ulFallBackCounter < 1000)
   {
      for(ulCount = 0; ulCount < 100; ulCount++)
      {
         ucPLLStatus = INREG8(0x3c0a);
         if(ucPLLStatus & PLLLOCK)
         {
            ulLockCount++;
         }
      }
   }

   *lpbLocked = ulLockCount >= 90;
}


- (void)G450SetPLLFreq:(long) f_out
{
   BOOL bFoundValidPLL;
   BOOL bLocked;
   CARD8  ucMisc;
   CARD32 ulMaxIndex;
   CARD32 ulMNP;
   CARD32 ulMNPTable[MNP_TABLE_SIZE];
   CARD32 ulIndex;
   CARD32 ulTryMNP;
   long lCompareResult;

   G450FindFirstPLLParam(f_out, &ulMNP);
   ulMNPTable[0] = ulMNP;
   G450FindNextPLLParam(f_out, &ulMNP);
   ulMaxIndex = 1;
   while(ulMNP != 0xffffffff)
   {
      int ulIndex;
      Bool bSkipValue;

      bSkipValue = FALSE;
      if(ulMaxIndex == MNP_TABLE_SIZE)
      {
         [self G450CompareMNP:f_out MNP: ulMNP MNP2: ulMNPTable[MNP_TABLE_SIZE - 1]
                        res: &lCompareResult];

         if(lCompareResult > 0)
         {
            bSkipValue = TRUE;
         }
         else
         {
            ulMaxIndex--;
         }
      }

      if(!bSkipValue)
      {
         for(ulIndex = ulMaxIndex; !bSkipValue && (ulIndex > 0); ulIndex--)
         {
            [self G450CompareMNP:f_out MNP: ulMNP MNP2: ulMNPTable[ulIndex - 1]
                           res: &lCompareResult];

            if(lCompareResult < 0)
            {
               ulMNPTable[ulIndex] = ulMNPTable[ulIndex - 1];
            }
            else
            {
               break;
            }
         }
         ulMNPTable[ulIndex] = ulMNP;
         ulMaxIndex++;
      }

      G450FindNextPLLParam(f_out, &ulMNP);
   }

   bFoundValidPLL = FALSE;
   ulMNP = 0;

   /* For pixel pll */
   ucMisc = INREG8(0x1FCC);
   OUTREG8(0x1fc2, (CARD8)(ucMisc | CLKSEL_MGA));    

   for(ulIndex = 0; !bFoundValidPLL && (ulIndex < ulMaxIndex); ulIndex++)
   {
      ulTryMNP = ulMNPTable[ulIndex];

/*    for(ucS = 0; !bFoundValidPLL && (ucS < 0x40); ucS += 8)*/
      {
/*         ulTryMNP &= 0xffffffc7;*/
/*         ulTryMNP |= (CARD32)ucS;*/
         
         bLocked = TRUE;
         if((ulMNPTable[ulIndex] & 0xff00) < 0x300 ||
            (ulMNPTable[ulIndex] & 0xff00) > 0x7a00)
         {
            bLocked = FALSE;
         }

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP - 0x300];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP + 0x300];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP - 0x200];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP + 0x200];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP - 0x100];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP + 0x100];
            [self G450IsPllLocked: &bLocked];
         }     

         if(bLocked)
         {
            [self G450WriteMNP: ulTryMNP];
            [self G450IsPllLocked: &bLocked];
         }     
         else if(!ulMNP)
         {
            [self G450WriteMNP: ulTryMNP];
            [self G450IsPllLocked: &bLocked];
            if(bLocked)
            {
               ulMNP = ulMNPTable[ulIndex]; 
            }
            bLocked = FALSE;
         }

         if(bLocked)
         {
            bFoundValidPLL = TRUE;
         }
      }
   }

   if(!bFoundValidPLL)
   {
      if(ulMNP)
      {
         [self G450WriteMNP: ulMNP];
      }
      else
      {
         [self G450WriteMNP: ulMNPTable[0]];
      }
   }
}

@end
