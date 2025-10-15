/*
 * Copyright © 1999-2007 Mirko Viviani. All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of the author may not be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * Created by Mirko Viviani 3 Apr 1999
 */

#import "MGA.h"
#import "XModes.h"


static const XMode X_640x480x60 = {
  TWO_MEGABYTES, 25175, 640, 664, 760, 800, 480, 491, 493, 525 };

static const XMode X_640x480x72 = {
  TWO_MEGABYTES, 31500, 640, 680, 720, 864, 480, 488, 491, 521 };

static const XMode X_640x480x75 = {
  TWO_MEGABYTES, 31500, 640, 656, 720, 840, 480, 481, 484, 500 };

static const XMode X_640x480x100 = {
  TWO_MEGABYTES, 45800, 640, 672, 768, 864, 480, 488, 494, 530 };

static const XMode X_800x512x62 = {
  TWO_MEGABYTES, 54375, 800, 800, 840, 848, 512, 512, 514, 515 };

static const XMode X_800x600x60 = {
  TWO_MEGABYTES, 40000, 800, 840, 968, 1056, 600, 601, 605, 628 };

static const XMode X_800x600x72 = {
  TWO_MEGABYTES, 50000, 800, 856, 976, 1040, 600, 637, 643, 666 };

static const XMode X_800x600x85 = {
  TWO_MEGABYTES, 60750, 800, 864, 928, 1088, 600, 616, 621, 657 };

static const XMode X_800x600x100 = {
  TWO_MEGABYTES, 69650, 800, 864, 928, 1088, 600, 604, 610, 640 };

///

static const XMode X_1024x768x60 = {
  TWO_MEGABYTES, 65000, 1024, 1032, 1176, 1344, 768, 771, 777, 806 };

static const XMode X_1024x768x60x24 = {
  FOUR_MEGABYTES, 65000, 1024, 1032, 1176, 1344, 768, 771, 777, 806 };

///

static const XMode X_1024x768x70 = {
  TWO_MEGABYTES, 75000, 1024, 1048, 1184, 1328, 768, 771, 777, 806 };

static const XMode X_1024x768x70x24 = {
  FOUR_MEGABYTES, 75000, 1024, 1048, 1184, 1328, 768, 771, 777, 806 };

///
static const XMode X_1024x768x76 = {
  TWO_MEGABYTES, 85000, 1024, 1032, 1152, 1360, 768, 784, 787, 823 };

static const XMode X_1024x768x76x24 = {
  FOUR_MEGABYTES, 85000, 1024, 1032, 1152, 1360, 768, 784, 787, 823 };

///
static const XMode X_1024x768x85 = {
  TWO_MEGABYTES, 98900, 1024, 1056, 1216, 1408, 768, 782, 788, 822 };

static const XMode X_1024x768x85x24 = {
  FOUR_MEGABYTES, 98900, 1024, 1056, 1216, 1408, 768, 782, 788, 822 };

///
static const XMode X_1024x768x100 = {
  TWO_MEGABYTES, 115500, 1024, 1056, 1248, 1440, 768, 771, 781, 802 };

static const XMode X_1024x768x100x24 = {
  FOUR_MEGABYTES, 115500, 1024, 1056, 1248, 1440, 768, 771, 781, 802 };

///
static const XMode X_1152x864x60 = {
  TWO_MEGABYTES, 89900, 1152, 1216, 1472, 1680, 864, 868, 876, 892 };

static const XMode X_1152x864x60x24 = {
  FOUR_MEGABYTES, 89900, 1152, 1216, 1472, 1680, 864, 868, 876, 892 };

///
static const XMode X_1152x864x70 = {
  TWO_MEGABYTES, 92000, 1152, 1208, 1368, 1474, 864, 865, 875, 895 };

static const XMode X_1152x864x70x24 = {
  FOUR_MEGABYTES, 92000, 1152, 1208, 1368, 1474, 864, 865, 875, 895 };

///
static const XMode X_1152x864x78 = {
  TWO_MEGABYTES, 110000, 1152, 1240, 1324, 1552, 864, 864, 876, 908 };

static const XMode X_1152x864x78x24 = {
  FOUR_MEGABYTES, 110000, 1152, 1240, 1324, 1552, 864, 864, 876, 908 };

///
static const XMode X_1152x864x84 = {
  TWO_MEGABYTES, 135000, 1152, 1464, 1592, 1776, 864, 864, 876, 908 };

static const XMode X_1152x864x84x24 = {
  FOUR_MEGABYTES, 135000, 1152, 1464, 1592, 1776, 864, 864, 876, 908 };

///
static const XMode X_1152x864x100 = {
  TWO_MEGABYTES, 137650, 1152, 1184, 1312, 1536, 864, 866, 885, 902 };

static const XMode X_1152x864x100x24 = {
  FOUR_MEGABYTES, 137650, 1152, 1184, 1312, 1536, 864, 866, 885, 902 };

///
static const XMode X_1280x1024x61 = {
  TWO_MEGABYTES, 110000, 1280, 1328, 1512, 1712, 1024, 1025, 1028, 1054 };

static const XMode X_1280x1024x61x16 = {
  FOUR_MEGABYTES, 110000, 1280, 1328, 1512, 1712, 1024, 1025, 1028, 1054 };

static const XMode X_1280x1024x61x24 = {
  EIGHT_MEGABYTES, 110000, 1280, 1328, 1512, 1712, 1024, 1025, 1028, 1054 };

///
static const XMode X_1280x1024x70 = {
  TWO_MEGABYTES, 126500, 1280, 1312, 1472, 1696, 1024, 1032, 1040, 1068 };

static const XMode X_1280x1024x70x16 = {
  FOUR_MEGABYTES, 126500, 1280, 1312, 1472, 1696, 1024, 1032, 1040, 1068 };

static const XMode X_1280x1024x70x24 = {
  EIGHT_MEGABYTES, 126500, 1280, 1312, 1472, 1696, 1024, 1032, 1040, 1068 };

///
static const XMode X_1280x1024x74 = {
  TWO_MEGABYTES, 135000, 1280, 1312, 1456, 1712, 1024, 1027, 1030, 1064 };

static const XMode X_1280x1024x74x16 = {
  FOUR_MEGABYTES, 135000, 1280, 1312, 1456, 1712, 1024, 1027, 1030, 1064 };

static const XMode X_1280x1024x74x24 = {
  EIGHT_MEGABYTES, 135000, 1280, 1312, 1456, 1712, 1024, 1027, 1030, 1064 };

///
static const XMode X_1280x1024x76 = {
  TWO_MEGABYTES, 135000, 1280, 1312, 1416, 1664, 1024, 1027, 1030, 1064 };

static const XMode X_1280x1024x76x16 = {
  FOUR_MEGABYTES, 135000, 1280, 1312, 1416, 1664, 1024, 1027, 1030, 1064 };

static const XMode X_1280x1024x76x24 = {
  EIGHT_MEGABYTES, 135000, 1280, 1312, 1416, 1664, 1024, 1027, 1030, 1064 };

///
static const XMode X_1280x1024x85 = {
  TWO_MEGABYTES, 157500, 1280, 1344, 1504, 1728, 1024, 1025, 1028, 1072 };

static const XMode X_1280x1024x85x16 = {
  FOUR_MEGABYTES, 157500, 1280, 1344, 1504, 1728, 1024, 1025, 1028, 1072 };

static const XMode X_1280x1024x85x24 = {
  EIGHT_MEGABYTES, 157500, 1280, 1344, 1504, 1728, 1024, 1025, 1028, 1072 };

///
static const XMode X_1280x1024x100 = {
  TWO_MEGABYTES, 181750, 1280, 1312, 1440, 1696, 1024, 1031, 1046, 1072 };

static const XMode X_1280x1024x100x16 = {
  FOUR_MEGABYTES, 181750, 1280, 1312, 1440, 1696, 1024, 1031, 1046, 1072 };

static const XMode X_1280x1024x100x24 = {
  EIGHT_MEGABYTES, 181750, 1280, 1312, 1440, 1696, 1024, 1031, 1046, 1072 };

///
static const XMode X_1440x900x60 = {
  TWO_MEGABYTES, 108840, 1440, 1472, 1880, 1912, 900, 918, 927, 946 };

static const XMode X_1440x900x60x16 = {
  FOUR_MEGABYTES, 108840, 1440, 1472, 1880, 1912, 900, 918, 927, 946 };

static const XMode X_1440x900x60x24 = {
  EIGHT_MEGABYTES, 108840, 1440, 1472, 1880, 1912, 900, 918, 927, 946 };

///
static const XMode X_1600x1000x90 = {
  TWO_MEGABYTES, 194875, 1600, 1616, 1744, 2080, 1000, 1001, 1004, 1041 };

static const XMode X_1600x1000x90x16 = {
  FOUR_MEGABYTES, 194875, 1600, 1616, 1744, 2080, 1000, 1001, 1004, 1041 };

static const XMode X_1600x1000x90x24 = {
  EIGHT_MEGABYTES, 194875, 1600, 1616, 1744, 2080, 1000, 1001, 1004, 1041 };

///

static const XMode X_1600x1024x60 = {
  TWO_MEGABYTES, 103125, 1600, 1600, 1656, 1664, 1024, 1024, 1029, 1030 };

static const XMode X_1600x1024x60x16 = {
  FOUR_MEGABYTES, 103125, 1600, 1600, 1656, 1664, 1024, 1024, 1029, 1030 };

static const XMode X_1600x1024x60x24 = {
  EIGHT_MEGABYTES, 103125, 1600, 1600, 1656, 1664, 1024, 1024, 1029, 1030 };

///
static const XMode X_1600x1024x90 = {
  TWO_MEGABYTES, 201090, 1600, 1616, 1760, 2096, 1024, 1025, 1028, 1066 };

static const XMode X_1600x1024x90x16 = {
  FOUR_MEGABYTES, 201090, 1600, 1616, 1760, 2096, 1024, 1025, 1028, 1066 };

static const XMode X_1600x1024x90x24 = {
  EIGHT_MEGABYTES, 201090, 1600, 1616, 1760, 2096, 1024, 1025, 1028, 1066 };

///
static const XMode X_1600x1200x60 = {
  TWO_MEGABYTES, 162000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x60x16 = {
  FOUR_MEGABYTES, 162000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x60x24 = {
  EIGHT_MEGABYTES, 162000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

///
static const XMode X_1600x1200x66 = {
  TWO_MEGABYTES, 177120, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1242 };

static const XMode X_1600x1200x66x16 = {
  FOUR_MEGABYTES, 177120, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1242 };

static const XMode X_1600x1200x66x24 = {
  EIGHT_MEGABYTES, 177120, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1242 };

///
static const XMode X_1600x1200x70 = {
  TWO_MEGABYTES, 189000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x70x16 = {
  FOUR_MEGABYTES, 189000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x70x24 = {
  EIGHT_MEGABYTES, 189000, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

///
static const XMode X_1600x1200x75 = {
  TWO_MEGABYTES, 202500, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x75x16 = {
  FOUR_MEGABYTES, 202500, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x75x24 = {
  EIGHT_MEGABYTES, 202500, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

///
static const XMode X_1600x1200x85 = {
  TWO_MEGABYTES, 229500, 1600, 1664, 1856, 2160, 1200, 1201, 12044, 1250 };

static const XMode X_1600x1200x85x16 = {
  FOUR_MEGABYTES, 229500, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

static const XMode X_1600x1200x85x24 = {
  EIGHT_MEGABYTES, 229500, 1600, 1664, 1856, 2160, 1200, 1201, 1204, 1250 };

///
static const XMode X_1792x1120x75 = {
  TWO_MEGABYTES, 204983, 1792, 1808, 1952, 2344, 1120, 1121, 1124, 1166 };

static const XMode X_1792x1120x75x16 = {
  FOUR_MEGABYTES, 204983, 1792, 1808, 1952, 2344, 1120, 1121, 1124, 1166 };

static const XMode X_1792x1120x75x24 = {
  EIGHT_MEGABYTES, 204983, 1792, 1808, 1952, 2344, 1120, 1121, 1124, 1166 };

///
static const XMode X_1792x1344x75 = {
  TWO_MEGABYTES, 261000, 1792, 1888, 2104, 2456, 1344, 1345, 1348, 1417 };

static const XMode X_1792x1344x75x16 = {
  EIGHT_MEGABYTES, 261000, 1792, 1888, 2104, 2456, 1344, 1345, 1348, 1417 };

static const XMode X_1792x1344x75x24 = {
  SIXTEEN_MEGABYTES, 261000, 1792, 1888, 2104, 2456, 1344, 1345, 1348, 1417 };

///
static const XMode X_1800x1440x64 = {
  FOUR_MEGABYTES, 230000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

static const XMode X_1800x1440x64x16 = {
  EIGHT_MEGABYTES, 230000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

static const XMode X_1800x1440x64x24 = {
  SIXTEEN_MEGABYTES, 230000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

///
static const XMode X_1800x1440x70 = {
  FOUR_MEGABYTES, 250000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

static const XMode X_1800x1440x70x16 = {
  EIGHT_MEGABYTES, 250000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

static const XMode X_1800x1440x70x24 = {
  SIXTEEN_MEGABYTES, 250000, 1800, 1896, 2088, 2392, 1440, 1441, 1444, 1490 };

///
static const XMode X_1856x1392x75 = {
  FOUR_MEGABYTES, 288000, 1856, 1984, 2208, 2560, 1392, 1393, 1396, 1500 };

static const XMode X_1856x1392x75x16 = {
  EIGHT_MEGABYTES, 288000, 1856, 1984, 2208, 2560, 1392, 1393, 1396, 1500 };

static const XMode X_1856x1392x75x24 = {
  SIXTEEN_MEGABYTES, 288000, 1856, 1984, 2208, 2560, 1392, 1393, 1396, 1500 };

///
static const XMode X_1920x1200x64 = {
  FOUR_MEGABYTES, 240500, 1920, 1980, 2100, 2700, 1200, 1201, 1210, 1400 };

static const XMode X_1920x1200x64x16 = {
  EIGHT_MEGABYTES, 240500, 1920, 1980, 2100, 2700, 1200, 1201, 1210, 1400 };

static const XMode X_1920x1200x64x24 = {
  SIXTEEN_MEGABYTES, 240500, 1920, 1980, 2100, 2700, 1200, 1201, 1210, 1400 };

///
static const XMode X_1920x1200x67 = {
  FOUR_MEGABYTES, 240500, 1920, 1980, 2100, 2550, 1200, 1201, 1210, 1400 };

static const XMode X_1920x1200x67x16 = {
  EIGHT_MEGABYTES, 240500, 1920, 1980, 2100, 2550, 1200, 1201, 1210, 1400 };

static const XMode X_1920x1200x67x24 = {
  SIXTEEN_MEGABYTES, 240500, 1920, 1980, 2100, 2550, 1200, 1201, 1210, 1400 };

///
static const XMode X_1920x1200x70 = {
  FOUR_MEGABYTES, 235357, 1920, 1936, 2096, 2528, 1280, 1281, 1284, 1330 };

static const XMode X_1920x1200x70x16 = {
  EIGHT_MEGABYTES, 235357, 1920, 1936, 2096, 2528, 1280, 1281, 1284, 1330 };

static const XMode X_1920x1200x70x24 = {
  SIXTEEN_MEGABYTES, 235357, 1920, 1936, 2096, 2528, 1280, 1281, 1284, 1330 };

///
static const XMode X_1920x1200x75 = {
  FOUR_MEGABYTES, 237000, 1920, 1936, 2096, 2528, 1200, 1201, 1204, 1250 };

static const XMode X_1920x1200x75x16 = {
  EIGHT_MEGABYTES, 237000, 1920, 1936, 2096, 2528, 1200, 1201, 1204, 1250 };

static const XMode X_1920x1200x75x24 = {
  SIXTEEN_MEGABYTES, 237000, 1920, 1936, 2096, 2528, 1200, 1201, 1204, 1250 };

///
static const XMode X_1920x1440x60 = {
  FOUR_MEGABYTES, 241380, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x60x16 = {
  EIGHT_MEGABYTES, 241380, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x60x24 = {
  SIXTEEN_MEGABYTES, 241380, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

///
static const XMode X_1920x1440x65 = {
  FOUR_MEGABYTES, 250000, 1920, 2008, 2158, 2600, 1440, 1444, 1446, 1480 };

static const XMode X_1920x1440x65x16 = {
  EIGHT_MEGABYTES, 250000, 1920, 2008, 2158, 2600, 1440, 1444, 1446, 1480 };

static const XMode X_1920x1440x65x24 = {
  SIXTEEN_MEGABYTES, 250000, 1920, 2008, 2158, 2600, 1440, 1444, 1446, 1480 };

///
static const XMode X_1920x1440x66 = {
  FOUR_MEGABYTES, 265518, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x66x16 = {
  EIGHT_MEGABYTES, 265518, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x66x24 = {
  SIXTEEN_MEGABYTES, 265518, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

///
static const XMode X_1920x1440x70 = {
  FOUR_MEGABYTES, 281610, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x70x16 = {
  EIGHT_MEGABYTES, 281610, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x70x24 = {
  SIXTEEN_MEGABYTES, 281610, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

///
static const XMode X_1920x1440x72 = {
  FOUR_MEGABYTES, 288900, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x72x16 = {
  EIGHT_MEGABYTES, 288900, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x72x24 = {
  SIXTEEN_MEGABYTES, 288900, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

///
static const XMode X_1920x1440x75 = {
  FOUR_MEGABYTES, 300000, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x75x16 = {
  EIGHT_MEGABYTES, 300000, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

static const XMode X_1920x1440x75x24 = {
  SIXTEEN_MEGABYTES, 300000, 1920, 1980, 2100, 2700, 1440, 1441, 1444, 1490 };

///
static const XMode X_2048x1280x60 = {
  FOUR_MEGABYTES, 243139, 2048, 2064, 2576, 3016, 1280, 1281, 1284, 1333 };

static const XMode X_2048x1280x60x16 = {
  EIGHT_MEGABYTES, 243139, 2048, 2064, 2576, 3016, 1280, 1281, 1284, 1333 };

static const XMode X_2048x1280x60x24 = {
  SIXTEEN_MEGABYTES, 243139, 2048, 2064, 2576, 3016, 1280, 1281, 1284, 1333 };

///
static const XMode X_2048x1536x60 = {
  FOUR_MEGABYTES, 268608, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x60x16 = {
  EIGHT_MEGABYTES, 268608, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x60x24 = {
  SIXTEEN_MEGABYTES, 268608, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

///
static const XMode X_2048x1536x65 = {
  FOUR_MEGABYTES, 285396, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x65x16 = {
  EIGHT_MEGABYTES, 285396, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x65x24 = {
  SIXTEEN_MEGABYTES, 285396, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

///
static const XMode X_2048x1536x68 = {
  FOUR_MEGABYTES, 299386, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x68x16 = {
  EIGHT_MEGABYTES, 299386, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

static const XMode X_2048x1536x68x24 = {
  SIXTEEN_MEGABYTES, 299386, 2048, 2124, 2276, 2798, 1536, 1537, 1540, 1572 };

///
static const XMode X_2304x1778x60 = {
  FOUR_MEGABYTES, 300000, 2304, 2316, 2466, 2804, 1728, 1729, 1732, 1778 };

static const XMode X_2304x1778x60x16 = {
  EIGHT_MEGABYTES, 300000, 2304, 2316, 2466, 2804, 1728, 1729, 1732, 1778 };

static const XMode X_2304x1778x60x24 = {
  SIXTEEN_MEGABYTES, 300000, 2304, 2316, 2466, 2804, 1728, 1729, 1732, 1778 };


const IODisplayInfo MGA_ModeTable[] =
{
	{
		/* 640 x 480 x 8 @ 60Hz. */
		640, 480, 640, 640, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_640x480x60,
	},
	{
		/* 640 x 480 x 8 @ 60Hz. */
		640, 480, 640, 640, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_640x480x60,
	},
	{
		/* 640 x 480 x 16 @ 60Hz. */
		640, 480, 640, 1280, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_640x480x60,
	},
	{
		/* 640 x 480 x 24 @ 60Hz. */
		640, 480, 640, 2560, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_640x480x60,
	},
	{
		/* 640 x 480 x 8 @ 72Hz. */
		640, 480, 640, 640, 72, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_640x480x72,
	},
	{
		/* 640 x 480 x 8 @ 72Hz. */
		640, 480, 640, 640, 72, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_640x480x72,
	},
	{
		/* 640 x 480 x 16 @ 72Hz. */
		640, 480, 640, 1280, 72, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_640x480x72,
	},
	{
		/* 640 x 480 x 24 @ 72Hz. */
		640, 480, 640, 2560, 72, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_640x480x72,
	},
	{
		/* 640 x 480 x 8 @ 75Hz. */
		640, 480, 640, 640, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_640x480x75,
	},
	{
		/* 640 x 480 x 8 @ 75Hz. */
		640, 480, 640, 640, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_640x480x75,
	},
	{
		/* 640 x 480 x 16 @ 75Hz. */
		640, 480, 640, 1280, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_640x480x75,
	},
	{
		/* 640 x 480 x 24 @ 75Hz. */
		640, 480, 640, 2560, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_640x480x75,
	},
	{
		/* 640 x 480 x 8 @ 100Hz. */
		640, 480, 640, 640, 100, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_640x480x100,
	},
	{
		/* 640 x 480 x 8 @ 100Hz. */
		640, 480, 640, 640, 100, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_640x480x100,
	},
	{
		/* 640 x 480 x 16 @ 100Hz. */
		640, 480, 640, 1280, 100, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_640x480x100,
	},
	{
		/* 640 x 480 x 24 @ 100Hz. */
		640, 480, 640, 2560, 100, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_640x480x100,
	},
	{
		/* 800 x 512 x 8 @ 62Hz. */
		800, 512, 800, 800, 62, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_800x512x62,
	},
	{
		/* 800 x 512 x 8 @ 62Hz. */
		800, 512, 800, 800, 62, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_800x512x62,
	},
	{
		/* 800 x 512 x 16 @ 62Hz. */
		800, 512, 800, 1600, 62, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_800x512x62,
	},
	{
		/* 800 x 512 x 24 @ 62Hz. */
		800, 512, 800, 3200, 62, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_800x512x62,
	},
	{
		/* 800 x 600 x 8 @ 60Hz. */
		800, 600, 800, 800, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_800x600x60,
	},
	{
		/* 800 x 600 x 8 @ 60Hz. */
		800, 600, 800, 800, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_800x600x60,
	},
	{
		/* 800 x 600 x 16 @ 60Hz. */
		800, 600, 800, 1600, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_800x600x60,
	},
	{
		/* 800 x 600 x 24 @ 60Hz. */
		800, 600, 800, 3200, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_800x600x60,
	},
	{
		/* 800 x 600 x 8 @ 72Hz. */
		800, 600, 800, 800, 72, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_800x600x72,
	},
	{
		/* 800 x 600 x 8 @ 72Hz. */
		800, 600, 800, 800, 72, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_800x600x72,
	},
	{
		/* 800 x 600 x 16 @ 72Hz. */
		800, 600, 800, 1600, 72, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_800x600x72,
	},
	{
		/* 800 x 600 x 24 @ 72Hz. */
		800, 600, 800, 3200, 72, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_800x600x72,
	},
	{
		/* 800 x 600 x 8 @ 85Hz. */
		800, 600, 800, 800, 85, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_800x600x85,
	},
	{
		/* 800 x 600 x 8 @ 85Hz. */
		800, 600, 800, 800, 85, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_800x600x85,
	},
	{
		/* 800 x 600 x 16 @ 85Hz. */
		800, 600, 800, 1600, 85, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_800x600x85,
	},
	{
		/* 800 x 600 x 24 @ 85Hz. */
		800, 600, 800, 3200, 85, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_800x600x85,
	},
	{
		/* 800 x 600 x 8 @ 100Hz. */
		800, 600, 800, 800, 100, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_800x600x100,
	},
	{
		/* 800 x 600 x 8 @ 100Hz. */
		800, 600, 800, 800, 100, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_800x600x100,
	},
	{
		/* 800 x 600 x 16 @ 100Hz. */
		800, 600, 800, 1600, 100, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_800x600x100,
	},
	{
		/* 800 x 600 x 24 @ 100Hz. */
		800, 600, 800, 3200, 100, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_800x600x100,
	},
	{
		/* 1024 x 768 x 8 @ 60Hz. */
		1024, 768, 1024, 1024, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1024x768x60,
	},
	{
		/* 1024 x 768 x 8 @ 60Hz. */
		1024, 768, 1024, 1024, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1024x768x60,
	},
	{
		/* 1024 x 768 x 16 @ 60Hz. */
		1024, 768, 1024, 2048, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1024x768x60,
	},
	{
		/* 1024 x 768 x 24 @ 60Hz. */
		1024, 768, 1024, 4096, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1024x768x60x24,
	},
	{
		/* 1024 x 768 x 8 @ 70Hz. */
		1024, 768, 1024, 1024, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1024x768x70,
	},
	{
		/* 1024 x 768 x 8 @ 70Hz. */
		1024, 768, 1024, 1024, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1024x768x70,
	},
	{
		/* 1024 x 768 x 16 @ 70Hz. */
		1024, 768, 1024, 2048, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1024x768x70,
	},
	{
		/* 1024 x 768 x 24 @ 70Hz. */
		1024, 768, 1024, 4096, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1024x768x70x24,
	},
	{
		/* 1024 x 768 x 8 @ 76Hz. */
		1024, 768, 1024, 1024, 76, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1024x768x76,
	},
	{
		/* 1024 x 768 x 8 @ 76Hz. */
		1024, 768, 1024, 1024, 76, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1024x768x76,
	},
	{
		/* 1024 x 768 x 16 @ 76Hz. */
		1024, 768, 1024, 2048, 76, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1024x768x76,
	},
	{
		/* 1024 x 768 x 24 @ 76Hz. */
		1024, 768, 1024, 4096, 76, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1024x768x76x24,
	},
	{
		/* 1024 x 768 x 8 @ 85Hz. */
		1024, 768, 1024, 1024, 85, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1024x768x85,
	},
	{
		/* 1024 x 768 x 8 @ 85Hz. */
		1024, 768, 1024, 1024, 85, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1024x768x85,
	},
	{
		/* 1024 x 768 x 16 @ 85Hz. */
		1024, 768, 1024, 2048, 85, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1024x768x85,
	},
	{
		/* 1024 x 768 x 24 @ 85Hz. */
		1024, 768, 1024, 4096, 85, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1024x768x85x24,
	},
	{
		/* 1024 x 768 x 8 @ 100Hz. */
		1024, 768, 1024, 1024, 100, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1024x768x100,
	},
	{
		/* 1024 x 768 x 8 @ 100Hz. */
		1024, 768, 1024, 1024, 100, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1024x768x100,
	},
	{
		/* 1024 x 768 x 16 @ 100Hz. */
		1024, 768, 1024, 2048, 100, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1024x768x100,
	},
	{
		/* 1024 x 768 x 24 @ 100Hz. */
		1024, 768, 1024, 4096, 100, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1024x768x100x24,
	},
	{
		/* 1152 x 864 x 8 @ 60Hz. */
		1152, 864, 1152, 1152, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1152x864x60,
	},
	{
		/* 1152 x 864 x 8 @ 60Hz. */
		1152, 864, 1152, 1152, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1152x864x60,
	},
	{
		/* 1152 x 864 x 16 @ 60Hz. */
		1152, 864, 1152, 2304, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1152x864x60,
	},
	{
		/* 1152 x 864 x 24 @ 60Hz. */
		1152, 864, 1152, 4608, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1152x864x60x24,
	},
	{
		/* 1152 x 864 x 8 @ 70Hz. */
		1152, 864, 1152, 1152, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1152x864x70,
	},
	{
		/* 1152 x 864 x 8 @ 70Hz. */
		1152, 864, 1152, 1152, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1152x864x70,
	},
	{
		/* 1152 x 864 x 16 @ 70Hz. */
		1152, 864, 1152, 2304, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1152x864x70,
	},
	{
		/* 1152 x 864 x 24 @ 70Hz. */
		1152, 864, 1152, 4608, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1152x864x70x24,
	},
	{
		/* 1152 x 864 x 8 @ 78Hz. */
		1152, 864, 1152, 1152, 78, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1152x864x78,
	},
	{
		/* 1152 x 864 x 8 @ 78Hz. */
		1152, 864, 1152, 1152, 78, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1152x864x78,
	},
	{
		/* 1152 x 864 x 16 @ 78Hz. */
		1152, 864, 1152, 2304, 78, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1152x864x78,
	},
	{
		/* 1152 x 864 x 24 @ 78Hz. */
		1152, 864, 1152, 4608, 78, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1152x864x78x24,
	},
	{
		/* 1152 x 864 x 8 @ 84Hz. */
		1152, 864, 1152, 1152, 84, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1152x864x84,
	},
	{
		/* 1152 x 864 x 8 @ 84Hz. */
		1152, 864, 1152, 1152, 84, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1152x864x84,
	},
	{
		/* 1152 x 864 x 16 @ 84Hz. */
		1152, 864, 1152, 2304, 84, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1152x864x84,
	},
	{
		/* 1152 x 864 x 24 @ 84Hz. */
		1152, 864, 1152, 4608, 84, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1152x864x84x24,
	},
	{
		/* 1152 x 864 x 8 @ 100Hz. */
		1152, 864, 1152, 1152, 100, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1152x864x100,
	},
	{
		/* 1152 x 864 x 8 @ 100Hz. */
		1152, 864, 1152, 1152, 100, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1152x864x100,
	},
	{
		/* 1152 x 864 x 16 @ 100Hz. */
		1152, 864, 1152, 2304, 100, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1152x864x100,
	},
	{
		/* 1152 x 864 x 24 @ 100Hz. */
		1152, 864, 1152, 4608, 100, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1152x864x100x24,
	},
	{
		/* 1280 x 1024 x 8 @ 61Hz. */
		1280, 1024, 1280, 1280, 61, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x61,
	},
	{
		/* 1280 x 1024 x 8 @ 61Hz. */
		1280, 1024, 1280, 1280, 61, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x61,
	},
	{
		/* 1280 x 1024 x 16 @ 61Hz. */
		1280, 1024, 1280, 2560, 61, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x61x16,
	},
	{
		/* 1280 x 1024 x 24 @ 61Hz. */
		1280, 1024, 1280, 5120, 61, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x61x24,
	},
	{
		/* 1280 x 1024 x 8 @ 70Hz. */
		1280, 1024, 1280, 1280, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x70,
	},
	{
		/* 1280 x 1024 x 8 @ 70Hz. */
		1280, 1024, 1280, 1280, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x70,
	},
	{
		/* 1280 x 1024 x 16 @ 70Hz. */
		1280, 1024, 1280, 2560, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x70x16,
	},
	{
		/* 1280 x 1024 x 24 @ 70Hz. */
		1280, 1024, 1280, 5120, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x70x24,
	},
	{
		/* 1280 x 1024 x 8 @ 74Hz. */
		1280, 1024, 1280, 1280, 74, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x74,
	},
	{
		/* 1280 x 1024 x 8 @ 74Hz. */
		1280, 1024, 1280, 1280, 74, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x74,
	},
	{
		/* 1280 x 1024 x 16 @ 74Hz. */
		1280, 1024, 1280, 2560, 74, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x74x16,
	},
	{
		/* 1280 x 1024 x 24 @ 74Hz. */
		1280, 1024, 1280, 5120, 74, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x74x24,
	},
	{
		/* 1280 x 1024 x 8 @ 76Hz. */
		1280, 1024, 1280, 1280, 76, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x76,
	},
	{
		/* 1280 x 1024 x 8 @ 76Hz. */
		1280, 1024, 1280, 1280, 76, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x76,
	},
	{
		/* 1280 x 1024 x 16 @ 76Hz. */
		1280, 1024, 1280, 2560, 76, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x76x16,
	},
	{
		/* 1280 x 1024 x 24 @ 76Hz. */
		1280, 1024, 1280, 5120, 76, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x76x24,
	},
	{
		/* 1280 x 1024 x 8 @ 85Hz. */
		1280, 1024, 1280, 1280, 85, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x85,
	},
	{
		/* 1280 x 1024 x 8 @ 85Hz. */
		1280, 1024, 1280, 1280, 85, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x85,
	},
	{
		/* 1280 x 1024 x 16 @ 85Hz. */
		1280, 1024, 1280, 2560, 85, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x85x16,
	},
	{
		/* 1280 x 1024 x 24 @ 85Hz. */
		1280, 1024, 1280, 5120, 85, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x85x24,
	},
	{
		/* 1280 x 1024 x 8 @ 100Hz. */
		1280, 1024, 1280, 1280, 100, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1280x1024x100,
	},
	{
		/* 1280 x 1024 x 8 @ 100Hz. */
		1280, 1024, 1280, 1280, 100, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1280x1024x100,
	},
	{
		/* 1280 x 1024 x 16 @ 100Hz. */
		1280, 1024, 1280, 2560, 100, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1280x1024x100x16,
	},
	{
		/* 1280 x 1024 x 24 @ 100Hz. */
		1280, 1024, 1280, 5120, 100, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1280x1024x100x24,
	},
	{
		/* 1440 x 900 x 8 @ 60Hz. */
		1440, 900, 1440, 1440, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1440x900x60,
	},
	{
		/* 1440 x 900 x 8 @ 60Hz. */
		1440, 900, 1440, 1440, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1440x900x60,
	},
	{
		/* 1440 x 900 x 16 @ 60Hz. */
		1440, 900, 1440, 2880, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1440x900x60,
	},
	{
		/* 1440 x 900 x 24 @ 60Hz. */
		1440, 900, 1440, 5760, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1440x900x60,
	},
	{
		/* 1600 x 1000 x 8 @ 90Hz. */
		1600, 1000, 1600, 1600, 90, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1000x90,
	},
	{
		/* 1600 x 1000 x 8 @ 90Hz. */
		1600, 1000, 1600, 1600, 90, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1000x90,
	},
	{
		/* 1600 x 1000 x 16 @ 90Hz. */
		1600, 1000, 1600, 3200, 90, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1000x90x16,
	},
	{
		/* 1600 x 1000 x 24 @ 90Hz. */
		1600, 1000, 1600, 6400, 90, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1000x90x24,
	},
	{
		/* 1600 x 1024 x 8 @ 60Hz. */
		1600, 1024, 1600, 1600, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1024x60,
	},
	{
		/* 1600 x 1024 x 8 @ 60Hz. */
		1600, 1024, 1600, 1600, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1024x90,
	},
	{
		/* 1600 x 1024 x 16 @ 60Hz. */
		1600, 1024, 1600, 3200, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1024x60x16,
	},
	{
		/* 1600 x 1024 x 24 @ 60Hz. */
		1600, 1024, 1600, 6400, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1024x60x24,
	},
	{
		/* 1600 x 1024 x 8 @ 90Hz. */
		1600, 1024, 1600, 1600, 90, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1024x90,
	},
	{
		/* 1600 x 1024 x 8 @ 90Hz. */
		1600, 1024, 1600, 1600, 90, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1024x90,
	},
	{
		/* 1600 x 1024 x 16 @ 90Hz. */
		1600, 1024, 1600, 3200, 90, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1024x90x16,
	},
	{
		/* 1600 x 1024 x 24 @ 90Hz. */
		1600, 1024, 1600, 6400, 90, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1024x90x24,
	},
	{
		/* 1600 x 1200 x 8 @ 60Hz. */
		1600, 1200, 1600, 1600, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1200x60,
	},
	{
		/* 1600 x 1200 x 8 @ 60Hz. */
		1600, 1200, 1600, 1600, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1200x60,
	},
	{
		/* 1600 x 1200 x 16 @ 60Hz. */
		1600, 1200, 1600, 3200, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1200x60x16,
	},
	{
		/* 1600 x 1200 x 24 @ 60Hz. */
		1600, 1200, 1600, 6400, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1200x60x24,
	},
	{
		/* 1600 x 1200 x 8 @ 66Hz. */
		1600, 1200, 1600, 1600, 66, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1200x66,
	},
	{
		/* 1600 x 1200 x 8 @ 66Hz. */
		1600, 1200, 1600, 1600, 66, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1200x66,
	},
	{
		/* 1600 x 1200 x 16 @ 66Hz. */
		1600, 1200, 1600, 3200, 66, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1200x66x16,
	},
	{
		/* 1600 x 1200 x 24 @ 66Hz. */
		1600, 1200, 1600, 6400, 66, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1200x66x24,
	},
	{
		/* 1600 x 1200 x 8 @ 70Hz. */
		1600, 1200, 1600, 1600, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1200x70,
	},
	{
		/* 1600 x 1200 x 8 @ 70Hz. */
		1600, 1200, 1600, 1600, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1200x70,
	},
	{
		/* 1600 x 1200 x 16 @ 70Hz. */
		1600, 1200, 1600, 3200, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1200x70x16,
	},
	{
		/* 1600 x 1200 x 24 @ 70Hz. */
		1600, 1200, 1600, 6400, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1200x70x24,
	},
	{
		/* 1600 x 1200 x 8 @ 75Hz. */
		1600, 1200, 1600, 1600, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1200x75,
	},
	{
		/* 1600 x 1200 x 8 @ 75Hz. */
		1600, 1200, 1600, 1600, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1200x75,
	},
	{
		/* 1600 x 1200 x 16 @ 75Hz. */
		1600, 1200, 1600, 3200, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1200x75x16,
	},
	{
		/* 1600 x 1200 x 24 @ 75Hz. */
		1600, 1200, 1600, 6400, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1200x75x24,
	},
	{
		/* 1600 x 1200 x 8 @ 85Hz. */
		1600, 1200, 1600, 1600, 85, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1600x1200x85,
	},
	{
		/* 1600 x 1200 x 8 @ 85Hz. */
		1600, 1200, 1600, 1600, 85, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1600x1200x85,
	},
	{
		/* 1600 x 1200 x 16 @ 85Hz. */
		1600, 1200, 1600, 3200, 85, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1600x1200x85x16,
	},
	{
		/* 1600 x 1200 x 24 @ 85Hz. */
		1600, 1200, 1600, 6400, 85, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1600x1200x85x24,
	},
	{
		/* 1792 x 1120 x 8 @ 75Hz. */
		1792, 1120, 1792, 1792, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1792x1120x75,
	},
	{
		/* 1792 x 1120 x 8 @ 75Hz. */
		1792, 1120, 1792, 1792, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1792x1120x75,
	},
	{
		/* 1792 x 1120 x 16 @ 75Hz. */
		1792, 1120, 1792, 3584, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1792x1120x75x16,
	},
	{
		/* 1792 x 1120 x 24 @ 75Hz. */
		1792, 1120, 1792, 7168, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1792x1120x75x24,
	},
	{
		/* 1792 x 1344 x 8 @ 75Hz. */
		1792, 1344, 1792, 1792, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1792x1344x75,
	},
	{
		/* 1792 x 1344 x 8 @ 75Hz. */
		1792, 1344, 1792, 1792, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1792x1344x75,
	},
	{
		/* 1792 x 1344 x 16 @ 75Hz. */
		1792, 1344, 1792, 3584, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1792x1344x75x16,
	},
	{
		/* 1792 x 1344 x 24 @ 75Hz. */
		1792, 1344, 1792, 7168, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1792x1344x75x24,
	},
	{
		/* 1800 x 1440 x 8 @ 64Hz. */
		1800, 1440, 1800, 1800, 64, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1800x1440x64,
	},
	{
		/* 1800 x 1440 x 8 @ 64Hz. */
		1800, 1440, 1800, 1800, 64, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1800x1440x64,
	},
	{
		/* 1800 x 1440 x 16 @ 64Hz. */
		1800, 1440, 1800, 3600, 64, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1800x1440x64x16,
	},
	{
		/* 1800 x 1440 x 24 @ 64Hz. */
		1800, 1440, 1800, 7200, 64, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1800x1440x64x24,
	},
	{
		/* 1800 x 1440 x 8 @ 70Hz. */
		1800, 1440, 1800, 1800, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1800x1440x70,
	},
	{
		/* 1800 x 1440 x 8 @ 70Hz. */
		1800, 1440, 1800, 1800, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1800x1440x70,
	},
	{
		/* 1800 x 1440 x 16 @ 70Hz. */
		1800, 1440, 1800, 3600, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1800x1440x70x16,
	},
	{
		/* 1800 x 1440 x 24 @ 70Hz. */
		1800, 1440, 1800, 7200, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1800x1440x70x24,
	},
	{
		/* 1856 x 1392 x 8 @ 75Hz. */
		1856, 1392, 1800, 1856, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1856x1392x75,
	},
	{
		/* 1856 x 1392 x 8 @ 75Hz. */
		1856, 1392, 1800, 1856, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1856x1392x75,
	},
	{
		/* 1856 x 1392 x 16 @ 75Hz. */
		1856, 1392, 1800, 3712, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1856x1392x75x16,
	},
	{
		/* 1856 x 1392 x 24 @ 75Hz. */
		1856, 1392, 1800, 7424, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1856x1392x75x24,
	},
	{
		/* 1920 x 1200 x 8 @ 64Hz. */
		1920, 1200, 1920, 1920, 64, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1200x64,
	},
	{
		/* 1920 x 1200 x 8 @ 64Hz. */
		1920, 1200, 1920, 1920, 64, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1200x64,
	},
	{
		/* 1920 x 1200 x 16 @ 64Hz. */
		1920, 1200, 1920, 3840, 64, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1200x64x16,
	},
	{
		/* 1920 x 1200 x 24 @ 64Hz. */
		1920, 1200, 1920, 7680, 64, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1200x64x24,
	},
	{
		/* 1920 x 1200 x 8 @ 67Hz. */
		1920, 1200, 1920, 1920, 67, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1200x67,
	},
	{
		/* 1920 x 1200 x 8 @ 67Hz. */
		1920, 1200, 1920, 1920, 67, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1200x67,
	},
	{
		/* 1920 x 1200 x 16 @ 67Hz. */
		1920, 1200, 1920, 3840, 67, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1200x67x16,
	},
	{
		/* 1920 x 1200 x 24 @ 67Hz. */
		1920, 1200, 1920, 7680, 67, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1200x67x24,
	},
	{
		/* 1920 x 1200 x 8 @ 70Hz. */
		1920, 1200, 1920, 1920, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1200x70,
	},
	{
		/* 1920 x 1200 x 8 @ 70Hz. */
		1920, 1200, 1920, 1920, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1200x70,
	},
	{
		/* 1920 x 1200 x 16 @ 70Hz. */
		1920, 1200, 1920, 3840, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1200x70x16,
	},
	{
		/* 1920 x 1200 x 24 @ 70Hz. */
		1920, 1200, 1920, 7680, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1200x70x24,
	},
	{
		/* 1920 x 1200 x 8 @ 75Hz. */
		1920, 1200, 1920, 1920, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1200x75,
	},
	{
		/* 1920 x 1200 x 8 @ 75Hz. */
		1920, 1200, 1920, 1920, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1200x75,
	},
	{
		/* 1920 x 1200 x 16 @ 75Hz. */
		1920, 1200, 1920, 3840, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1200x75x16,
	},
	{
		/* 1920 x 1200 x 24 @ 75Hz. */
		1920, 1200, 1920, 7680, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1200x75x24,
	},
	{
		/* 1920 x 1440 x 8 @ 60Hz. */
		1920, 1440, 1920, 1920, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x60,
	},
	{
		/* 1920 x 1440 x 8 @ 60Hz. */
		1920, 1440, 1920, 1920, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x60,
	},
	{
		/* 1920 x 1440 x 16 @ 60Hz. */
		1920, 1440, 1920, 3840, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x60x16,
	},
	{
		/* 1920 x 1440 x 24 @ 60Hz. */
		1920, 1440, 1920, 7680, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x60x24,
	},
	{
		/* 1920 x 1440 x 8 @ 65Hz. */
		1920, 1440, 1920, 1920, 65, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x65,
	},
	{
		/* 1920 x 1440 x 8 @ 65Hz. */
		1920, 1440, 1920, 1920, 65, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x65,
	},
	{
		/* 1920 x 1440 x 16 @ 65Hz. */
		1920, 1440, 1920, 3840, 65, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x65x16,
	},
	{
		/* 1920 x 1440 x 24 @ 65Hz. */
		1920, 1440, 1920, 7680, 65, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x65x24,
	},
	{
		/* 1920 x 1440 x 8 @ 66Hz. */
		1920, 1440, 1920, 1920, 66, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x66,
	},
	{
		/* 1920 x 1440 x 8 @ 66Hz. */
		1920, 1440, 1920, 1920, 66, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x66,
	},
	{
		/* 1920 x 1440 x 16 @ 66Hz. */
		1920, 1440, 1920, 3840, 66, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x66x16,
	},
	{
		/* 1920 x 1440 x 24 @ 66Hz. */
		1920, 1440, 1920, 7680, 66, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x66x24,
	},
	{
		/* 1920 x 1440 x 8 @ 70Hz. */
		1920, 1440, 1920, 1920, 70, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x70,
	},
	{
		/* 1920 x 1440 x 8 @ 70Hz. */
		1920, 1440, 1920, 1920, 70, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x70,
	},
	{
		/* 1920 x 1440 x 16 @ 70Hz. */
		1920, 1440, 1920, 3840, 70, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x70x16,
	},
	{
		/* 1920 x 1440 x 24 @ 70Hz. */
		1920, 1440, 1920, 7680, 70, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x70x24,
	},
	{
		/* 1920 x 1440 x 8 @ 72Hz. */
		1920, 1440, 1920, 1920, 72, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x72,
	},
	{
		/* 1920 x 1440 x 8 @ 72Hz. */
		1920, 1440, 1920, 1920, 72, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x72,
	},
	{
		/* 1920 x 1440 x 16 @ 72Hz. */
		1920, 1440, 1920, 3840, 72, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x72x16,
	},
	{
		/* 1920 x 1440 x 24 @ 72Hz. */
		1920, 1440, 1920, 7680, 72, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x72x24,
	},
	{
		/* 1920 x 1440 x 8 @ 75Hz. */
		1920, 1440, 1920, 1920, 75, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_1920x1440x75,
	},
	{
		/* 1920 x 1440 x 8 @ 75Hz. */
		1920, 1440, 1920, 1920, 75, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_1920x1440x75,
	},
	{
		/* 1920 x 1440 x 16 @ 75Hz. */
		1920, 1440, 1920, 3840, 75, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_1920x1440x75x16,
	},
	{
		/* 1920 x 1440 x 24 @ 75Hz. */
		1920, 1440, 1920, 7680, 75, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_1920x1440x75x24,
	},
	{
		/* 2048 x 1280 x 8 @ 60Hz. */
		2048, 1280, 2048, 2048, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_2048x1280x60,
	},
	{
		/* 2048 x 1280 x 8 @ 60Hz. */
		2048, 1280, 2048, 2048, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_2048x1280x60,
	},
	{
		/* 2048 x 1280 x 16 @ 60Hz. */
		2048, 1280, 2048, 4096, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_2048x1280x60x16,
	},
	{
		/* 2048 x 1280 x 24 @ 60Hz. */
		2048, 1280, 2048, 8192, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_2048x1280x60x24,
	},
	{
		/* 2048 x 1536 x 8 @ 60Hz. */
		2048, 1536, 2048, 2048, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_2048x1536x60,
	},
	{
		/* 2048 x 1536 x 8 @ 60Hz. */
		2048, 1536, 2048, 2048, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_2048x1536x60,
	},
	{
		/* 2048 x 1536 x 16 @ 60Hz. */
		2048, 1536, 2048, 4096, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_2048x1536x60x16,
	},
	{
		/* 2048 x 1536 x 24 @ 60Hz. */
		2048, 1536, 2048, 8192, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_2048x1536x60x24,
	},
	{
		/* 2048 x 1536 x 8 @ 65Hz. */
		2048, 1536, 2048, 2048, 65, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_2048x1536x65,
	},
	{
		/* 2048 x 1536 x 8 @ 65Hz. */
		2048, 1536, 2048, 2048, 65, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_2048x1536x65,
	},
	{
		/* 2048 x 1536 x 16 @ 65Hz. */
		2048, 1536, 2048, 4096, 65, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_2048x1536x65x16,
	},
	{
		/* 2048 x 1536 x 24 @ 65Hz. */
		2048, 1536, 2048, 8192, 65, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_2048x1536x65x24,
	},
	{
		/* 2048 x 1536 x 8 @ 68Hz. */
		2048, 1536, 2048, 2048, 68, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_2048x1536x68,
	},
	{
		/* 2048 x 1536 x 8 @ 68Hz. */
		2048, 1536, 2048, 2048, 68, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_2048x1536x60,
	},
	{
		/* 2048 x 1536 x 16 @ 68Hz. */
		2048, 1536, 2048, 4096, 68, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_2048x1536x68x16,
	},
	{
		/* 2048 x 1536 x 24 @ 68Hz. */
		2048, 1536, 2048, 8192, 68, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_2048x1536x68x24,
	},
	{
		/* 2304 x 1778 x 8 @ 60Hz. */
		2304, 1778, 2304, 2304, 60, 0, IO_8BitsPerPixel,
		IO_OneIsWhiteColorSpace, "WWWWWWWW", 0, (void *)&X_2304x1778x60,
	},
	{
		/* 2304 x 1778 x 8 @ 60Hz. */
		2304, 1778, 2304, 2304, 60, 0, IO_8BitsPerPixel,
		IO_RGBColorSpace, "PPPPPPPP", 0, (void *)&X_2304x1778x60,
	},
	{
		/* 2304 x 1778 x 16 @ 60Hz. */
		2304, 1778, 2304, 4608, 60, 0, IO_15BitsPerPixel,
		IO_RGBColorSpace, "-RRRRRGGGGGBBBBB", 0, (void *)&X_2304x1778x60x16,
	},
	{
		/* 2304 x 1778 x 24 @ 60Hz. */
		2304, 1778, 2304, 9216, 60, 0, IO_24BitsPerPixel,
		IO_RGBColorSpace, "--------RRRRRRRRGGGGGGGGBBBBBBBB", 0, (void *)&X_2304x1778x60x24,
	}
};


const int MGA_ModeTableCount =
	(sizeof(MGA_ModeTable) / sizeof(MGA_ModeTable[0]));

const int MGA_defaultMode = 0;
