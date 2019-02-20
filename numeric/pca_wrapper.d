/* module d_glat.numeric.pca_wrapper; */

/* import d_glat.numeric.core; */
/* import d_glat.numeric.svd; */

/* /++ */
/* original JS code: */

/* function pca_impl(X) { */
/*         /\* */
/*           Return matrix of all principle components as column vectors */
/*         *\/         */
/*         var m = X.length; */
/*         var sigma = numeric.div(numeric.dot(numeric.transpose(X), X), m); */
/*         return numeric.svd(sigma).U; */
/*     } */
/* +/ */

/* double[][] numeric_pca_wrapper( in double[][] X ) */
/* { */
/*   immutable m = X.length; */
/*   immutable sigma = numeric_div( numeric_dot( numeric_transpose( X ) */
/*                                               , X */
/*                                               ) */
/*                                  , m */
/*                                  ); */

/*   return numeric_svd( sigma ).U; */
/* } */


/* // ------------------------------------------------------------ */

/* unittest */
/* { */
/*   import std.math: approxEqual; */
  
/*   /\* example taken from Lubeck *\/ */
  
/*   double[][] ingredients = [ */
/*                             [ 7,  26,   6,  60 ], */
/*                             [ 1,  29,  15,  52 ], */
/*                             [ 11,  56,   8,  20 ], */
/*                             [ 11,  31,   8,  47 ], */
/*                             [ 7,  52,   6,  33 ], */
/*                             [ 11,  55,   9,  22 ], */
/*                             [ 3,  71,  17,   6 ], */
/*                             [ 1,  31,  22,  44 ], */
/*                             [ 2,  54,  18,  22 ], */
/*                             [ 21,  47,   4,  26 ], */
/*                             [ 1,  40,  23,  34 ], */
/*                             [ 11,  66,   9,  12 ], */
/*                             [ 10,  68,   8,  12 ] ]; */
  
/*   auto res = ingedients.numeric_pca_wrapper; */
    
/*   auto coeff = */
/*     [ */
/*      [ -0.067799985695474,  -0.646018286568728,   0.567314540990512,   0.506179559977705 ], */
/*      [ -0.678516235418647,  -0.019993340484099,  -0.543969276583817,   0.493268092159297 ], */
/*      [ 0.029020832106229,   0.755309622491133,   0.403553469172668,   0.515567418476836 ], */
/*      [ 0.730873909451461,  -0.108480477171676,  -0.468397518388289,   0.484416225289198 ] */
/*      ]; */
  
/*   assert(equal!approxEqual(res, coeff)); */
/* } */
