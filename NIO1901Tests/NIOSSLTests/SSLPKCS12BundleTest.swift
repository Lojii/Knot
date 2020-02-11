//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import XCTest
import NIO
@testable import NIOSSL


/// This is a base64-PKCS12 file that contains only samplePemCert and
/// samplePemKey, no extra certs. The passphrase is
/// "thisisagreatpassword".
let base64EncodedSimpleP12 = """
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
"""


/// This is a base64-PKCS12 file that contains samplePemCert and
/// samplePemKey as the main cert and key, and then extra certs
/// multiSanCert, multiCNCert, noCNCert, and unicodeCNCert. The
/// passphrase is "thisisagreatpassword".
let base64EncodedComplexP12 = """
MIIdiQIBAzCCHU8GCSqGSIb3DQEHAaCCHUAEgh08MIIdODCCE28GCSqGSIb3
DQEHBqCCE2AwghNcAgEAMIITVQYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQYw
DgQI1FOPOf48OAgCAggAgIITKOaK3r7p3wDsGDjbO5yBp+MA7UelAOiUNilU
cNcoJtNsGJmKL+MRvhD8YekoQ9lUg1T4CFmWmgIRVcLDBmOlOScv6/VFTl2T
AgRO6cqW7QyZBi13G5wJhvIPjb+zdhZMhBN1R6145oFnDinFi65yPeui2ohn
s+GKH0r2sJm4hMu/O8YejtItwQJwbC4Vzasa/pR6XFsXw/MNzzIql7ofziV+
LuiZlE2z+9Ulzxn6Zaqg0B5wDa15iKk3bPe4fpAGZUu656GYYrLZMKBC39xL
xEhzu7H5P/AF5ilIbMnVwAeRoeh5vDgs28j7gGXgklTBYJukWKAqE8bOWabd
bddwDTCRb+ifvDFnYDSeEXLkmaA12jLEx8NF0MsUoptCq81fGbXkbUPvyU5l
YrL1BRnisU4KnDqBDSvu5RLpOUNSq2RDfQvusSx7nXwfavM/RYHSuPEM0kQK
XgzOU//lfXmuITnp50hy4CzYeaVhrAlTbfY+98DvKmI/go0otVNFbh9n99rU
nwXb6tUduYlfxE2HRWaPBrA5SYF+hQJomMNqj7odeELlq6MAOqa1vzKdo270
zXAp2lpRp5jmC7RXAJV2GKoIvdfDYBc6vci2tsyha9KqNJWZowHsStLA5fyE
3IO3cz5reW9izGdNn4pUAsoh8aAA6MS7cnpPqUUk3vIaAsNxcFdWk7JBDDWA
KFVYVQRPOLRvxVyNs/wp3ySda2Dz48aoH6tCvTg6m15iRN4AKh82SBVT13ko
jrHlIfTNvcj16ZDzXn6nQH/jKvkLhLEkBiav7+UIKzx2WvnjqBisBVRBSzqB
84diJrK1jHKX8yW5A+RshMcX74H2oS4yddxRAnoCRLsSu+rGoGnDw5a0kgs7
070wN/gE9Nl92pfy8h5G36Gzy9jU3XpfINehCc2XRVGQoCDo/bLvHMnnXzw9
Chyr2/CEPDc2x/l8B22ptoBAU1qFxjq+wGP2ysbmKgQ85LVsLXOJpiInG1g+
nuWBCi+xRRs3TsoTTGOF7yXV6+Tq9J0uorQehaLkAud0NKhwvuZIasWtrzWE
QnSQ+rc9u4HkuoIJHnAnBOIIMtcRutiuqSKdUCV8XrpuLeCDBpb0FBWPYQRT
bp/fN1rtjwTLoyYi+pfFX2cLExnVSx6eJ79Vi7BTCF/3lx9/CeA/jWgNkBVv
+F592quY9oKfg/46aBL/XMMb8H2n1MfBrAXH/2A5cM13BY98P1GzeQ6t7yM5
sR3/Qk1fu4151tsf3unsESIFjr2GiPZVjD5UWlOgCKViIP1UWKAOvPptXac/
IAsQeiMKLQqDAC52pcf74o/o2FJrn31qyaMh4373ItCES5yNGEoRYPRWbydG
mNYYOmCjfH3xvmH5j1YGhmppO+psO9B3K42UYoZkpzuFFtRRZnTxLP22SjTO
Wwt6x8MuDOetqL85F9Dw/ph/l5Ec1iNFQl7uDczLEKakVFOYTzSstbUWNvAl
ZfzjdWb2bSLKjRSVC4T3CK/MqVD8VKuquag167yEJzrgiIGfJ5FX+NRPg/Po
mzy2YNivMbKXGFet3ZzYqjBvwGBjFNTmRf9jmWtSZ+TOoHaQu6aPLJzdjmsx
AyyMgezr0lhdDdVjlcq3o9mBW3nENHChDPQ76h+NqqwE9WkVX+c8YAG/BvWM
NXPYc2cOZhuhPHXfjsPIeyUS3xxuDNLWVihu/zpPNvcZFV+14EC52elwtTGI
LRb8ugunBynyRx+YWVY90sGos8U+GLS8K1uWtnC4m9pIXzvTn3kGruxipQRs
R2qfwZqaVDQoGwIzKzVxao7HDPKhHk5QApmWRMpKTWrqaLaqBpVD1aoB9Z8U
mOEOWwP8kMbm2xD8vk9V5OWnqkmJyFNHjuzAohmGN7KcyHICDOYhbkmPxCxV
Qgytc0QX6pEzxHKSRjeCYS3KoqLcLhJEC+5Ou3tdLmfk2WY8H27fuXydqXVY
x6UMVPtpKH+ZsJFl3B7PS4qGjoeqI3OuMpeLry6DYVZvaSPPKOen8Ca4qA8H
L5xvGMSHmOKxXMqOm19E0xk8DKgRQUu+2hCgzKqV9re/h2IE+cE2H6NXztvf
rH5U3ZI6v+7FetXy0DAVwyhqqpoV35lqMFRuvchSXsJ75Q0oQ9786PK9U6hl
VsVqVW6pY+T/HUHWv/bLSGIyl7jla3ElVTpRRapQ19ZsVivVpgLYi05EKv4U
+/SCnaVCYuqt3xj58HTW6pvqFsxemJyn1qgFVTxqEJ+fNMWopnTKtAA41ch6
OKO9p9KE5cT4YNR5VcpUpPpSUuB5JG9djAn7dZAsn2XiiNmTv8yBXqwuO3y8
lkn5bau1LWvp8vMWCV7zmQy+wcfB+B5zYrUm9hYbLX+GM22hGdVuOxktRxtp
aVdQwIMVwh2/4dnGz5VAOaJgpcnrpNLlIOMhIAgCeeqn4RnhJhmSgRqr4PBi
G5LnV4gV8l/K5aG0ba03YtiEdvS4W09wFr2AwSXxUV9vhbsufNS0HxioQEmp
xZ1EJpahpUiGmFHtItv0hp4Pba+4/ZvpgbP3BtaVXQsYDdpQ/0Tt6S9zwrhY
fcAP58fFw3QyjxUoPNhXtcA+NoEdq77zCuByJnS9CWDWMVcpYRqE5eGpCQcT
y32kMnRc1DUcOHtK9WzuJVX/cQ0Rmy56hhNSNX577ceAHbfi3WcBUoXERvMZ
1v34EQ5l88fmBn7gwieNfOxKacLad8mYoLyA8KWMKwwCmDVrwtqpcv78bs1Y
7sMt4sJWm85/87AaacuaZyufhZ8+8vju3QvC+aQHPJmQ+U3EERgvD/hx9vaf
lPNHBTu0TP+gie+bHpm69eJ0irtAUIt2A74fsWIhu7PLNIAoT2sFcMpLa4Hi
NbM5c9h+Q8cibXFjF0FLvDb0kEHW7uBubNHHPbHVcqkVPkDJ7PSMEjrFK7OF
k5wHIaiWm1EacpH1CDv+P1WshulwV0HReY3RyboGtQrH6n7ph/bRiWSQaPYC
N0L5UbHiiN+4VE96oP/Or6gvCMkEqDza7sv2mQOxNW+2Ntz6GJEkucwq2UMC
QWWUcKEW866bbRVd2ceVDIOZE7DhY+FSRiNYoWvIVAPYKV9UC8V6wdojvLww
Y/TZ/4XXqKmNEZWGnVrIDV/eI+AhnD0KKNWwapyuQWgNwikAashL48jk8PCu
k6oS5z6PBXpIs8oKsBJcONAngHKxCotVzUhaiyiwjvYCDPX/rYuJZ3ABz1sd
4O3DLkn8Ep0FpKuyGtOhaTeqtmVRM7DHH2I4qB96H7ljP7AooILXj3o1Jq9Q
tQ4xp9Cyb31hQg+G5ERGPDgtLSq7BtJUyoicHO6mEJiThhP4m/99miuk/MTI
yK0V0iwxOfGOjmjC76+mypNd4fEbPd/SWr+sglBdJKh5ALipYugEfBWHZo4l
Np7v4I+FuuiuCNXuQNPEi7qe2b9n+jKKtWnviyAgtgmx0JxLwAfvRuEHX0qA
8JhpG4yiKCtg/oEsvFxXCLVCKd9ywCCwq39d0CnN+PFji0pCAp5pai3WlibA
5lloadn6cSGH9BzU0Nkz5e7uQmrRkllkkORto7SwpmimYmU5xQijqZIlO/7N
8DzrnZcALrhojViHUrCjgigpLsMNKia/+tqMj07PXuh/lh7MM8qVs3L+XATi
I+9AMcjXI/wLQxyItyHsg0gAQB0rL/gTW1A/TZratZr8FdUwp/mn9UoLeyAt
Wp0kNgiCPhTIpNyQyEBJAlPJSPqKrnGBPga5UZZY+MUJf1JqBt28p29lMnm8
3x7kdPqBaBVe1xmJGoAOV4vBK30M///L+IorPGNEilixkhkz/YHEZwAE2NOs
Ciq7Ikr3vodhwKclWyH0v5y7C9F+1q8U+61/YcUCJVcy/jEMWenS47ejYKXu
VCZ23RkwSCg6MceQ3hLFjvsYJyXJJRzCEIdQUXDTetyAmZM2WQYQVYlFk98C
ZQktu2G7OJM9W5FnsuI/3QmMyBFjnE3La1vOtf9RwISdwqWH8tjpaY6aRV0X
+Ict0B6BJLslFxWILVg2t6S8hRTEXryzfh1teHkdFQbJ3FzhvQOaW5AJ8GWD
l9BWCLwSd4IyQ4XqbdTyRFJ1kqfYhyf9ViChZNMnHVr1vyLOpaFw8yzlIkUq
dR23PSTHrh4uFTw8XdNpuiTGW1Tvdg1ajV+rukMVbJK/KYWRNp1a13+ElI/g
52m4Ha+Yl9lkqZNPAI/hYxfHqmoiiAPVvgjtZdY7Fw3xCTdVuuw9kAnz5uOk
yvmTwPXOH3EX3Y9TM5UvBL+kN3yH3e2Uycsie5kqNcUVfsbP95K4a6qIcFtk
lgDk9k6hqFWuQ+xyfgQL9AJv1QDM0Rq0/0+5svYs0bloPXjIWv4w1ftxiZh5
lvikKDiW8f0ia9eUpgm9wpkBRz3flnhHN3EbAKu204hXBdpHrGPF4hde4iCR
5h46QTflT4+uATgsjKeDRNHSlJotylXi9fDIkF+5FvbAI4NuGbNuYVGBO5Dc
RZcE8laiol9BA8WqMy8iznZW9+GzTdH6I8VyNsllVl2Bn0/zYPsOgKgJUd4y
2GsrU98I0Z+VH+o2uvdsHu5DR5mNm0D0p8o6jrOOTp8WM2vdcbDrO9LX5ohP
Vhb5Ag5rvmeUcdv6nA1jwV8VpKbmuO5pqhZRDuUBG9zBKwmkk9INVpjxc5AP
ONKaSwhhpEi1x0tQSBWrZr3DTVmtrGi48klWIAtOCVTMBXnS85JN2HqQVgu0
jooki5k8XU38dPsbJ4ZW+Z4l85DDvmZIDUOsdXtGDMPYBn/ZEVTFqGNrRvDd
fo+viaUZvMZsyAsRItupapd64arkH0o6yKijRSB0XlMOmkbTCk+bk22XGjz3
iWaoXJlssQlOjhje6A/OB17Rl1nCnJXmI/YPfuC99skgkW1AGqBzLYYJxxiJ
OP4qHUabr563AdLEs2n6zoBff2hufTFcBbIw9xEyiiYnpIJHC+ADHCqQuJnw
6GGEp2Tv5nqdAhR1jBqnr9TlH1GUC3c2mEC/t9C/slJtY/VYg/JvNN/IFBzz
Ppu0JjUdkZyoPl4SD7Yqu8zarcUpxGRSSUKwKSQNW6G4U1lkqzrXogUFSc7o
Cp8AlTntRVf8mKTKfunqw1CrLQ0FeeDVtlsrYtQZdYVpMoMP3Ckpb3HRazhk
OC8Dwq+9LaZRJxqQSnufhYQneqHa6wdrWzIpLyX74+gCGR5Bqi9FEc0+B6Ot
NyNbztac+HxuPmj+VrmCr8Dbekau2ViJ3W7nE2FBzgwc2+pSddXVIRs59IUa
QnJUa4F5YB0WgwAta2MoJ+fNYk+dV13rrwcIpZbVHemS7hYOm5pP6pkdb6Al
LDoELX0M1xjxMvMByG4uEZcI+brza0BKp+rMDcf8O24komjO2apEltLZpONG
5iDjtKacrvGM4yYwAHJgY2fmg26HYlwv94gM3JS+mL7m+ossM4GjLJSBKnzK
wSIhwITtd3LMTlVFr58R8ytZwn8JKmsyh+7rBSmpq1jE5Jx4pyz9sxFtidzQ
q44fkAMgoeuqLwo3WOsjdwpOXeFrrYLy0I7lQ0NQwCU2dTy+JweOJy/rjClx
GUzzsCgXd18hICO47QeA1hY+pxpBZQnachzBH47VN03Um2wZaK+EJbpIaKJ+
O/ehnzQju2CbStW1EysrD9G0/MHrRgHInOKvIsnJEIwlksEAZNzEiM+v3Y+H
hgFWmEkmrePLQBgw9oS1wg2pCJzFarPxITHO+E7E1xAmfUXflvgooQbnOM0V
BDoF1Dpxy3yhxkqXPaedKWThhhNlcIlmdpl1W575kY1RBrztQo2HCFeXJIQi
MVSYQ0+tGwXyml1uZTZ8dlX+8wC7BN0GBiraYBw4ahMki+TsfPPsPzrygSsu
cExavBjez5WsEzAusw+0mBjpC2lR6ynTwI5z/4XpU/sQYZermAPhGAsvLpT3
nhMAgB9KNO9CQQZYgwzIA5QrlY6DC4hlBPSa/ICu0XMOA4c9amhcgXgFJEUj
8uT1sfTcFDdRsIPqsszinEcGvgPTaw5XcJIS3owN8Rp7DjFO3gywPeVV788k
NGun8cXF6Qea5neHeKavM91SGYpeyHR75ZS+k/ErZJ3rJ/MBrlNy9aTM8M/a
z6Z5IoXddeodf9Ugj3F8HPZjVfFECX+Hq7kd/32BEAHVsctDLjBkPUTOI3oF
cqFuFQE5Oz04wnF587bodl4qKUv2ghaBkpINl1oJkr0GKleN4Uma8P9dOmD7
1oy2YjQytQ2rmpUIJFWxkg9ffZqqawlzKqQn6kIAGKVKx5AtSuDasSQSo2u+
w6YL4I042QNndjiZI4FHxmH72nw8Td19ljiy9a54kCISfom4nBhbb2+I4saX
15kbrWLn4lbbmxF9cSNzDIWQoC0uRqFHbbqvfeamvNg3T8IwBd1D4VAoKgW9
Z6CGVQGUxHVN0NBk0Y0Z/cTX8uLe9A4tHmAxqOcFQTmegFW7HY2YbNCU99/o
+BphRHp7Uw8OLpisKzi7/UZatazpPnV5K1kNisWcy20q835zeU1x/oJQtejL
OIrTK5p1aa6PnQr83fd6fN05MIIJwQYJKoZIhvcNAQcBoIIJsgSCCa4wggmq
MIIJpgYLKoZIhvcNAQwKAQKgggluMIIJajAcBgoqhkiG9w0BDAEDMA4ECDje
zkPin9gMAgIIAASCCUhJe0uJLIvZERU7JtQgspaBeKRKDH71glq9ZOioDq5O
B35+xV3F9v5RvLKveo3cRi79FaR/J2RRZVx29guL8orL+bPwqdgSAGquynL9
A/kFbgP5OYKkaQIGldQ/6X5E2BQ/zLPE9Pj+Dj7ERNfYnWL9n2jXLrEe3ZU4
8w2Gko0KxE36rwxwgxAkNnxO3odGMt2FIkktpxOWpkI8sECzxf5UV1yoYhSx
T8sxXcwFO+bIH85TolHTCSgBoM39Z69BZmlCIzRp5+h0TiYnacNwOiY5ugaI
tRczyCbY0zXuCV38gAgMqQpfrNKpsv0zC5ro99B45/GiCBe0Kc8wP62xlfDW
AzPVZbp0Jv8DB7YOoOn7nXbHMrg07wMmRcbEKk/1nLM0ZoULTWY1lLD0UPtQ
YvNunuD6Qgzx6rRlMu6vk2LoXfJ84wXe86pgnDPwmebnVYLwVObrCi5GXQXc
LRDNxUoNRoQJk2qJyugFjNfQKKWCTmRxpunlu7HwMgLKkbEjvLDmMjZ7UA8m
daNfzXfzKimOzFUUGSicf0SHV02dKWFbYo/P+iIqTJX/Vlpb21tFkDUU6UK3
oLGInUvnHTHsKfDsCACN9dTkGaHVlfQKgg4AY+GXXd9c+gyS4Ahd7hQmjqs9
B5WJfKqRZ/k6XUTqfOF8SIWjrivR/ymMskZeJklCQ9btXwFKePX1PulZ9CI8
NSZxXl5zsOQjsx+zxFzhGCiW1sNQTAkiUEbMBE51v5lOXosk9SSQ2LYoIeIj
sc33GQAVxE53rrsNF4XxVTKXS8f94L86wERL5OXHQOGmw0s2lacJ7xITJPtl
WqJpwnGqvp8izAfQepjkw+gf0QPTTImk04fDgu+1PcObZYlNFxUjQ6OEAymY
B85Ts1fdQU6Pjq+bEo65vPb59+6Pa6K51WkT2FA+kVKm0FG2ACH+YB7iowgF
cC8H3/KBKfeFL4MUCJECIxnKj9q4O1NHpW9ELgehTd+voR9Tfz5T8NYBlc/J
omXXXsRC1CyNOe2eUmUnwv3w094uBDbt+hkKcjtHfFJ2qb1bRn8SC+EynXX+
Abrge3bgOly/YAhq5Dy2Gv8OblJTgXTyMWz3/U5kkd2wRXSUtmmsuBq90DO5
YKwNst5h/j48QwO1oz5IVpbFLOAOXYeOMo5nqzDcErgh7S39FcoHWegNF5ln
EfCh9VgQN33TX0ycO6HaykHj9DGIWjgGLeDeic6Ot03cPWlb1zEVSypAjYxp
GYWjNWTUMEnRLFIXF9tXcnLI6dFzi8XtSoOIWmWQfOdDhk5PtWkeRx8NIi6Q
2y0JoP0NMp/YA4Fst97CXEmxA9RkF6F/sdH3K39xCKbSKLBLvEvbjAS2Qnuf
a+Hg4Oo1/c+og6oHlV8Z5czjx86Ccsha9O9359/Q1MvWYRucqEX8uJtZhP58
Fr0HmkYeczP1qpNd5rABSpl8a+sQAe/3dj0TANoCxN8E5sZN9MsbGy6u9PEm
OMn/AqJ/ts9ya/dtHtDdx5cY0lIbKv/D4GJurbRY6nrhu5l7lFw2w5Ask5ib
FJQ3Q/DsJig+i4eA3Hq/oiFvq198gQbjy15HcIUQEP/6hgvkR3sxpjGqxytr
KxQXCOANxhzz8lyjHOqLiLDDnmOj3KRXdLBh6UO/iMa480DRHWnfr8I0J5a4
4a9GksPTtu/BSHqKs8Mr1p+VGjrZO6n6sAgs9/1+amo2lKQ4MriVzSvHPJzt
xD0cxWdYwvnZG1KVgmVe2GvW83jFkH7MPwco1lNRS6QIKxcNC8wc4u8PNAej
51SbfARpuM2jVTJaECxarRt84OuShXYghwQsci20Tkdz9H/ZNVfV/v+JLC95
6iOyQr3MtfOXSUnSXL+I5cb3uq0Bvnv11rHQfLMuhLbPfon9sRasZHmKfvfI
3A0J6fcH0sEwOXBZTu4TT3Riuju2q0eZyBmhl+k8GmrDZnBh9eN8enBYljWD
z6dMTpfp0cF0BTv47r1HqEsUOLwURQR2Q/eNxM6vk6hxYXleCqNmJv+l8Rqn
BGLRCh8aIy9CHOP34dRA1Dwfsf4WVOrNkBuxBoAhSoHBEIJErJTq9INWrBp1
wJDH/sy7kEwj7sYBXIFeIx2r7LsAad4akuwdXEMbZVeguF2WPXNPYWQeb6R0
PVFKz5mMBIgJf7ZtQYtt24xTCeSZVeLX4I9IkVhglwy/63n+gniZwSq5X4er
SAtlRL01cN+yTDlf4gE6RoYYwrdQITgo6NaAfSgvG1Za87u8aFKmR6C7m4aE
F7yc1U6Krf2n7ufTqvH64DkPiDooZ0hsx3VateiKO1q8ljFpvZGkiHkk+vu4
1IgnoVJOL0iREBdSy0IIGIeVN9A6RtHfht+FrwoTqoGLeGMEXNW1H4YhHxjX
lbu42EREs45eI3jBdly0BhapkEtvu5A1kg/Q1uZ7BwVhbFcMbcYxkWBjxam6
Wy6GOSOl8PA9IVndX/bUvIyEp+gsiZfNQDTaafuGJ6YKwMOubS3rXg5LXspz
NzWmt1bAEGQXcV6iKHCbg9NfvDJG6Ka6oWtxTNtfiDBMpqkwfKh0qplhmh8T
MQ8mgZmJYyWTaxqjgkny7HsX/1sbmr9w/uQMb3Z+oWfZfcgDsRsKc2l0jlGy
zJUrqSNtTSQ2514gxt87UDYASFVuOfgD6NJ8z5T0uO3UunoHSN0nT5/rhrPJ
8dY3B17rTs0D2HwVoW/5W4hZULffNqQZIROUiB8ji3o8yTYqgGl9E6bOA9cF
zDfRPLPvL7RZVxUa9cyfhbkmLN4zWLDsngYe694H5VL9FXPhDtCLK60kY3vi
5YsvOJ8O1nRsKvqial/KPy39TgK09qAbDkNFYZAS2SMQR5RvmZ9oeItCVK79
IRAk9VIbnSj7pDMwxfvM1Rt2fFUu1VtrOd4YS9KsLtVIvowbyXNCDf41VdVS
f3q5IQ6Ud9TQLxMF78031jRBNTmw11mpM70X5qadkxr+edCCO+hGmT433Xxs
t/HYgr5FUh6MV/b/0runUDbBo2PZu2fNutDFEEm8I1MrwrKgmcXNScgOMBJr
eQjJ8bstzEijLoW57G530fHi1xhLj4HyKvCGGsGLxAQnmQZwd6yvz2Rme6+m
tlF6DR1qBO0YnmtaXjZpoveQcFLDpn8kAf0YHEWTcGv+2ZiYF7I8Jpokv27a
thgINn0xJTAjBgkqhkiG9w0BCRUxFgQUV35Zua6X4Zjx+lcZ9w9kqnshTbQw
MTAhMAkGBSsOAwIaBQAEFC9mlQ2bgjJlBI2nmTqAAL/CTILuBAjTjTK3aRzy
qQICCAA=
"""

let base64EncodedNoPassP12 = """
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
"""


var simpleP12: [UInt8] {
    return Array(Data(base64Encoded: base64EncodedSimpleP12, options: .ignoreUnknownCharacters)!)
}


var complexP12: [UInt8] {
    return Array(Data(base64Encoded: base64EncodedComplexP12, options: .ignoreUnknownCharacters)!)
}


var noPassP12: [UInt8] {
    return Array(Data(base64Encoded: base64EncodedNoPassP12, options: .ignoreUnknownCharacters)!)
}


class SSLPKCS12BundleTest: XCTestCase {
    static var simpleFilePath: String! = nil
    static var complexFilePath: String! = nil
    static var noPassFilePath: String! = nil

    override class func setUp() {
        SSLPKCS12BundleTest.simpleFilePath = try! dumpToFile(data: Data(base64Encoded: base64EncodedSimpleP12,
                                                                        options: .ignoreUnknownCharacters)!)
        SSLPKCS12BundleTest.complexFilePath = try! dumpToFile(data: Data(base64Encoded: base64EncodedComplexP12,
                                                                         options: .ignoreUnknownCharacters)!)
        SSLPKCS12BundleTest.noPassFilePath = try! dumpToFile(data: Data(base64Encoded: base64EncodedNoPassP12,
                                                                        options: .ignoreUnknownCharacters)!)
    }

    override class func tearDown() {
        _ = unlink(SSLPKCS12BundleTest.simpleFilePath)
        _ = unlink(SSLPKCS12BundleTest.complexFilePath)
        _ = unlink(SSLPKCS12BundleTest.noPassFilePath)
    }

    func testDecodingSimpleP12FromMemory() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(buffer: simpleP12, passphrase: "thisisagreatpassword".utf8)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert])
    }

    func testDecodingComplexP12FromMemory() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(buffer: complexP12, passphrase: "thisisagreatpassword".utf8)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)
        let caOne = try NIOSSLCertificate(buffer: Array(multiSanCert.utf8CString), format: .pem)
        let caTwo = try NIOSSLCertificate(buffer: Array(multiCNCert.utf8CString), format: .pem)
        let caThree = try NIOSSLCertificate(buffer: Array(noCNCert.utf8CString), format: .pem)
        let caFour = try NIOSSLCertificate(buffer: Array(unicodeCNCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert, caOne, caTwo, caThree, caFour])
    }

    func testDecodingSimpleP12FromMemoryWithoutPassphrase() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(buffer: noPassP12)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert])
    }

    func testDecodingSimpleP12FromFile() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(file: SSLPKCS12BundleTest.simpleFilePath, passphrase: "thisisagreatpassword".utf8)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert])
    }

    func testDecodingComplexP12FromFile() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(file: SSLPKCS12BundleTest.complexFilePath, passphrase: "thisisagreatpassword".utf8)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)
        let caOne = try NIOSSLCertificate(buffer: Array(multiSanCert.utf8CString), format: .pem)
        let caTwo = try NIOSSLCertificate(buffer: Array(multiCNCert.utf8CString), format: .pem)
        let caThree = try NIOSSLCertificate(buffer: Array(noCNCert.utf8CString), format: .pem)
        let caFour = try NIOSSLCertificate(buffer: Array(unicodeCNCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert, caOne, caTwo, caThree, caFour])
    }

    func testDecodingSimpleP12FromFileWithoutPassphrase() throws {
        let p12Bundle = try NIOSSLPKCS12Bundle(file: SSLPKCS12BundleTest.noPassFilePath)
        let expectedKey = try NIOSSLPrivateKey(buffer: Array(samplePemKey.utf8CString), format: .pem)
        let expectedCert = try NIOSSLCertificate(buffer: Array(samplePemCert.utf8CString), format: .pem)

        XCTAssertEqual(p12Bundle.privateKey, expectedKey)
        XCTAssertEqual(p12Bundle.certificateChain, [expectedCert])
    }

    func testDecodingNonExistentPKCS12File() throws {
        do {
            _ = try NIOSSLPKCS12Bundle(file: "/nonexistent/path")
            XCTFail("Did not throw")
        } catch let error as IOError {
            XCTAssertEqual(error.errnoCode, ENOENT)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

