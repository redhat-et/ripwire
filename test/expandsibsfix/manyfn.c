// expandsibsfix/manyfn.c — the CAPPED case for test/expandsibscheck.sh: 145 sibling functions
// (kMaxExpandSibs=100, so sibs_capped="1" with sibs_total="144") and 30 includes
// (kMaxExpandIncludes=24, so inc_capped="1" with inc_total="30"). Both counts are DELIBERATE:
// ONE OVER each cap, so the fixture keeps exercising the truncation it exists to prove. Grown
// 45 -> 145 on 2026-09-10 when the sibs cap was raised 8 -> 100; at 45 the cap no longer fired and
// this gate would have passed while testing nothing.
#include "hdr00.h"
#include "hdr01.h"
#include "hdr02.h"
#include "hdr03.h"
#include "hdr04.h"
#include "hdr05.h"
#include "hdr06.h"
#include "hdr07.h"
#include "hdr08.h"
#include "hdr09.h"
#include "hdr10.h"
#include "hdr11.h"
#include "hdr12.h"
#include "hdr13.h"
#include "hdr14.h"
#include "hdr15.h"
#include "hdr16.h"
#include "hdr17.h"
#include "hdr18.h"
#include "hdr19.h"
#include "hdr20.h"
#include "hdr21.h"
#include "hdr22.h"
#include "hdr23.h"
#include "hdr24.h"
#include "hdr25.h"
#include "hdr26.h"
#include "hdr27.h"
#include "hdr28.h"
#include "hdr29.h"

int manyFn000( void )
{
    return 0;
}

int manyFn001( void )
{
    return 1;
}

int manyFn002( void )
{
    return 2;
}

int manyFn003( void )
{
    return 3;
}

int manyFn004( void )
{
    return 4;
}

int manyFn005( void )
{
    return 5;
}

int manyFn006( void )
{
    return 6;
}

int manyFn007( void )
{
    return 7;
}

int manyFn008( void )
{
    return 8;
}

int manyFn009( void )
{
    return 9;
}

int manyFn010( void )
{
    return 10;
}

int manyFn011( void )
{
    return 11;
}

int manyFn012( void )
{
    return 12;
}

int manyFn013( void )
{
    return 13;
}

int manyFn014( void )
{
    return 14;
}

int manyFn015( void )
{
    return 15;
}

int manyFn016( void )
{
    return 16;
}

int manyFn017( void )
{
    return 17;
}

int manyFn018( void )
{
    return 18;
}

int manyFn019( void )
{
    return 19;
}

int manyFn020( void )
{
    return 20;
}

int manyFn021( void )
{
    return 21;
}

int manyFn022( void )
{
    return 22;
}

int manyFn023( void )
{
    return 23;
}

int manyFn024( void )
{
    return 24;
}

int manyFn025( void )
{
    return 25;
}

int manyFn026( void )
{
    return 26;
}

int manyFn027( void )
{
    return 27;
}

int manyFn028( void )
{
    return 28;
}

int manyFn029( void )
{
    return 29;
}

int manyFn030( void )
{
    return 30;
}

int manyFn031( void )
{
    return 31;
}

int manyFn032( void )
{
    return 32;
}

int manyFn033( void )
{
    return 33;
}

int manyFn034( void )
{
    return 34;
}

int manyFn035( void )
{
    return 35;
}

int manyFn036( void )
{
    return 36;
}

int manyFn037( void )
{
    return 37;
}

int manyFn038( void )
{
    return 38;
}

int manyFn039( void )
{
    return 39;
}

int manyFn040( void )
{
    return 40;
}

int manyFn041( void )
{
    return 41;
}

int manyFn042( void )
{
    return 42;
}

int manyFn043( void )
{
    return 43;
}

int manyFn044( void )
{
    return 44;
}

int manyFn045( void )
{
    return 45;
}

int manyFn046( void )
{
    return 46;
}

int manyFn047( void )
{
    return 47;
}

int manyFn048( void )
{
    return 48;
}

int manyFn049( void )
{
    return 49;
}

int manyFn050( void )
{
    return 50;
}

int manyFn051( void )
{
    return 51;
}

int manyFn052( void )
{
    return 52;
}

int manyFn053( void )
{
    return 53;
}

int manyFn054( void )
{
    return 54;
}

int manyFn055( void )
{
    return 55;
}

int manyFn056( void )
{
    return 56;
}

int manyFn057( void )
{
    return 57;
}

int manyFn058( void )
{
    return 58;
}

int manyFn059( void )
{
    return 59;
}

int manyFn060( void )
{
    return 60;
}

int manyFn061( void )
{
    return 61;
}

int manyFn062( void )
{
    return 62;
}

int manyFn063( void )
{
    return 63;
}

int manyFn064( void )
{
    return 64;
}

int manyFn065( void )
{
    return 65;
}

int manyFn066( void )
{
    return 66;
}

int manyFn067( void )
{
    return 67;
}

int manyFn068( void )
{
    return 68;
}

int manyFn069( void )
{
    return 69;
}

int manyFn070( void )
{
    return 70;
}

int manyFn071( void )
{
    return 71;
}

int manyFn072( void )
{
    return 72;
}

int manyFn073( void )
{
    return 73;
}

int manyFn074( void )
{
    return 74;
}

int manyFn075( void )
{
    return 75;
}

int manyFn076( void )
{
    return 76;
}

int manyFn077( void )
{
    return 77;
}

int manyFn078( void )
{
    return 78;
}

int manyFn079( void )
{
    return 79;
}

int manyFn080( void )
{
    return 80;
}

int manyFn081( void )
{
    return 81;
}

int manyFn082( void )
{
    return 82;
}

int manyFn083( void )
{
    return 83;
}

int manyFn084( void )
{
    return 84;
}

int manyFn085( void )
{
    return 85;
}

int manyFn086( void )
{
    return 86;
}

int manyFn087( void )
{
    return 87;
}

int manyFn088( void )
{
    return 88;
}

int manyFn089( void )
{
    return 89;
}

int manyFn090( void )
{
    return 90;
}

int manyFn091( void )
{
    return 91;
}

int manyFn092( void )
{
    return 92;
}

int manyFn093( void )
{
    return 93;
}

int manyFn094( void )
{
    return 94;
}

int manyFn095( void )
{
    return 95;
}

int manyFn096( void )
{
    return 96;
}

int manyFn097( void )
{
    return 97;
}

int manyFn098( void )
{
    return 98;
}

int manyFn099( void )
{
    return 99;
}

int manyFn100( void )
{
    return 100;
}

int manyFn101( void )
{
    return 101;
}

int manyFn102( void )
{
    return 102;
}

int manyFn103( void )
{
    return 103;
}

int manyFn104( void )
{
    return 104;
}

int manyFn105( void )
{
    return 105;
}

int manyFn106( void )
{
    return 106;
}

int manyFn107( void )
{
    return 107;
}

int manyFn108( void )
{
    return 108;
}

int manyFn109( void )
{
    return 109;
}

int manyFn110( void )
{
    return 110;
}

int manyFn111( void )
{
    return 111;
}

int manyFn112( void )
{
    return 112;
}

int manyFn113( void )
{
    return 113;
}

int manyFn114( void )
{
    return 114;
}

int manyFn115( void )
{
    return 115;
}

int manyFn116( void )
{
    return 116;
}

int manyFn117( void )
{
    return 117;
}

int manyFn118( void )
{
    return 118;
}

int manyFn119( void )
{
    return 119;
}

int manyFn120( void )
{
    return 120;
}

int manyFn121( void )
{
    return 121;
}

int manyFn122( void )
{
    return 122;
}

int manyFn123( void )
{
    return 123;
}

int manyFn124( void )
{
    return 124;
}

int manyFn125( void )
{
    return 125;
}

int manyFn126( void )
{
    return 126;
}

int manyFn127( void )
{
    return 127;
}

int manyFn128( void )
{
    return 128;
}

int manyFn129( void )
{
    return 129;
}

int manyFn130( void )
{
    return 130;
}

int manyFn131( void )
{
    return 131;
}

int manyFn132( void )
{
    return 132;
}

int manyFn133( void )
{
    return 133;
}

int manyFn134( void )
{
    return 134;
}

int manyFn135( void )
{
    return 135;
}

int manyFn136( void )
{
    return 136;
}

int manyFn137( void )
{
    return 137;
}

int manyFn138( void )
{
    return 138;
}

int manyFn139( void )
{
    return 139;
}

int manyFn140( void )
{
    return 140;
}

int manyFn141( void )
{
    return 141;
}

int manyFn142( void )
{
    return 142;
}

int manyFn143( void )
{
    return 143;
}

int manyFn144( void )
{
    return 144;
}
