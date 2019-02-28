module d_glat.flatmatrix.lib_svd;

public import d_glat.flatmatrix.core_matrix;

import std.exception;
import std.math;

struct SvdResult
{
  size_t m;
  size_t n;
  
  Matrix U;  // m*n

  double[] q; // n (diagonal of S)
  Matrix S;  // n*n (diagonal)

  Matrix V;  // n*n
  Matrix VT; // n*n

  // Buffer for internal computations
  // (put here for the inplace version)
  
  double[] e; // n

  // --- API

  this( in size_t m, in size_t n ) pure nothrow @safe
  {
    setDim( m, n );
  }

  void setDim( in size_t m, in size_t n ) pure nothrow @safe
  {
    pragma( inline, true );
    if (this.m != m  ||  this.n != n)
      {
        this.m = m;
        this.n = n;

        this.U   = Matrix([m, n]);
        this.q   = new double[ n ];
        this.S   = Matrix([n, n]);
        this.V   = Matrix([n, n]);
        this.VT  = Matrix([n, n]);
        this.e   = new double[ n ];
      }
  }
};

SvdResult svd( in Matrix A ) pure @safe
//Compute the thin SVD from G. H. Golub and C. Reinsch, Numer. Math. 14, 403-420 (1970)
{
  debug assert( A.ndim == 2 );

  immutable m = A.nrow;
  immutable n = A.ncol;

  enforce( m >= n, "Need more rows than columns" );

  auto ret = SvdResult( m, n );
  
  bool converged = svd_inplace( A, ret );
  enforce( converged, "SVD error: did not converge." );

  return ret;
}

bool svd_inplace( in ref Matrix A
                  , ref SvdResult ret
                  ) pure nothrow @safe @nogc
/*
  Compute the thin SVD from G. H. Golub and C. Reinsch, Numer. Math. 14, 403-420 (1970)

  Returns `true` if it converged, `false` otherwise.
*/
{
  pragma( inline, true );
  
  debug assert( A.ndim == 2 );

  immutable m= A.nrow;
  immutable n= A.ncol;

  debug
    {
      assert( m >= n );
      assert( m == ret.m );
      assert( n == ret.n );
    }
  
  double[] u;
  double[] q;
  double[] v;
  double[] e;

  // Init: as fast as possible

  clone_inplace( A, ret.U );

  u = ret.U.data;

  q = ret.q;

  v = ret.V.data;
  v[] = 0.0;

  e = ret.e;
  
  double temp;
  double prec= numeric_epsilon; //Math.pow(2,-52) // assumes double prec
  double tolerance= 1e-64/prec;
  long itmax= 50;
  double c=0.0;
  long i=0;
  long j=0;
  long k=0;
  long l=0;
  
  e[] = 0.0;
  q[] = 0.0;
  
  double pythag( in double a_0, in double b_0 )
  {
    auto a = abs(a_0 );
    auto b = abs(b_0);

    if (a > b)
      return a*sqrt(1.0+(b*b/a/a));

    else if (b == 0.0) 
      return a;

    return b*sqrt(1.0+(a*a/b/b));
  }

  //Householder's reduction to bidiagonal form

  double f= 0.0;
  double g= 0.0;
  double h= 0.0;
  double x= 0.0;
  double y= 0.0;
  double z= 0.0;
  double s= 0.0;

  long rowi_offset, rowj_offset, rowk_offset
    ,  j_l1_offset, j_i_offset, j_k_offset
    ,  k_i_offset, k_j_offset
    ;
  
  for (i=0, rowi_offset = 0; i < n; i++, rowi_offset += n)
    {
      e[i]= g;
      s= 0.0;
      l= i+1;

      for (j=i, rowj_offset = j*n; j < m; j++, rowj_offset += n)
        {
          // s += (u[j][i]*u[j][i]);
          double tmp = u[ rowj_offset + i ];
          s += tmp*tmp;
        }

      if (s <= tolerance)
        g= 0.0;
      else
        {
          // f= ui[i];
          auto ii_offset = rowi_offset + i;
          f= u[ ii_offset ];
          
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g-s;

          // ui[i]=f-g;
          u[ ii_offset ]=f-g;

          for (j=l; j < n; j++)
            {
              s= 0.0;
              for (k=i, rowk_offset = k * n; k < m; k++, rowk_offset += n)
                {
                  // s += u[k][i]*u[k][j];
                  s += u[ rowk_offset + i ] * u[ rowk_offset + j ];
                }

              f= s/h;

              for (k=i, rowk_offset = k * n; k < m; k++, rowk_offset += n)
                {
                  // u[k][j]+=f*u[k][i];
                  u[ rowk_offset + j ] += f * u[ rowk_offset + i ];
                }
            }
        }
      q[i]= g;
      s= 0.0;
      for (j=l; j < n; j++)
        {
          // s= s + ui[j]*ui[j];
          double tmp = u[ rowi_offset + j ];
          s += tmp * tmp;
        }
      
      if (s <= tolerance)
        g= 0.0;
      else
        {	
          //f= ui[i+1];
          auto i_ip1_offset = rowi_offset + i + 1; 
          f = u[ i_ip1_offset ];
          
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g - s;

          // ui[i+1] = f-g;
          u[ i_ip1_offset ] = f-g;
          
          // for (j=l; j < n; j++) e[j]= ui[j]/h;
          for (j=l; j < n; j++) e[j]= u[ rowi_offset + j ]/h;
          
          for (j=l, rowj_offset = j*n; j < m; j++, rowj_offset += n)
            {	
              s=0.0;
              for (k=l; k < n; k++)
                {
                  //s += (u[j][k]*ui[k]);
                  s += (u[ rowj_offset + k ] * u[ rowi_offset + k ]);
                }
              
              for (k=l; k < n; k++)
                {
                  // u[j][k]+=s*e[k];
                  u[ rowj_offset + k ] += s*e[k];
                }
            }	
        }
      y= abs(q[i])+abs(e[i]);
      if (y>x) 
        x=y;
    }
  
  // accumulation of right hand gtransformations
  for (i=n-1, rowi_offset = i * n; i != -1; i+= -1, rowi_offset -= n)
    {
      if (g != 0.0)
        {
          // h= g*ui[i+1];
          h= g*u[ rowi_offset + i+1];
          
          for (j=l, rowj_offset = j*n; j < n; j++, rowj_offset += n)
            {
              // v[j][i]=ui[j]/h;
              v[ rowj_offset + i ]=u[ rowi_offset + j ]/h;
            }
          for (j=l; j < n; j++)
            {	
              s=0.0;
              for (k=l, rowk_offset = k*n; k < n; k++, rowk_offset += n)
                {
                  // s += ui[k]*v[k][j];
                  s += u[ rowi_offset + k ] * v[ rowk_offset + j ];
                }

              for (k=l, rowk_offset = k*n; k < n; k++, rowk_offset += n)
                {
                  // v[k][j]+=(s*v[k][i]);
                  v[ rowk_offset + j ] += (s*v[ rowk_offset + i ]);
                }
            }	
        }

      for (j=l, rowj_offset = j * n; j < n; j++, rowj_offset += n)
        {
          // vi[j] = 0.0;
          v[ rowi_offset + j ] = 0.0;
          
          // v[j][i] = 0.0;
          v[ rowj_offset + i ] = 0.0;
        }

      // vi[i] = 1.0;
      v[ rowi_offset + i ] = 1.0;

      g= e[i];
      l= i;
    }
  
  // accumulation of left hand transformations
  for (i=n-1,  rowi_offset = i * n; i != -1; i+= -1, rowi_offset -= n)
    {	
      l= i+1;
      g= q[i];
      for (j=l; j < n; j++) 
        {
          // ui[j] = 0.0;
          u[ rowi_offset + j ] = 0.0;
        }

      auto ii_offset = rowi_offset + i;
      
      if (g != 0.0)
        {
          // h= ui[i]*g;
          h= u[ ii_offset]*g;
          
          for (j=l; j < n; j++)
            {
              s=0.0;

              // for (k=l; k < m; k++) s += u[k][i]*u[k][j];
              for (k=l,  rowk_offset = k*n; k < m; k++, rowk_offset += n)
                {
                  // s += u[k][i]*u[k][j];
                  s += u[ rowk_offset + i ] * u[ rowk_offset + j ];
                }
              
              f= s/h;
              // for (k=i; k < m; k++) u[k][j]+=f*u[k][i];
              for (k=i,  rowk_offset = k * n; k < m; k++, rowk_offset += n)
                {
                  // u[k][j]+=f*u[k][i];
                  u[ rowk_offset + j ] += f * u[ rowk_offset + i ];
                }
            }
          // for (j=i; j < m; j++) u[j][i] = u[j][i]/g;
          for (j=i,  rowj_offset = j*n; j < m; j++, rowj_offset += n)
            {
              // u[j][i] = u[j][i]/g;
              u[ rowj_offset + i ] /= g;
            }
        }
      else
        {
          // for (j=i; j < m; j++) u[j][i] = 0.0;
          for (j=i,  rowj_offset = j*n; j < m; j++, rowj_offset += n)
            {
              // u[j][i] = 0.0;
              u[ rowj_offset + i ] = 0.0;
            }
        }

      // ui[i] += 1.0;
      u[ ii_offset ] += 1.0;
    }
  
  // diagonalization of the bidiagonal form
  prec= prec*x;
  for (k=n-1; k != -1; k+= -1)
    {
      for (long iteration=0; iteration < itmax; iteration++)
        {	// test f splitting
          bool test_convergence = false;
            for (l=k; l != -1; l+= -1)
              {	
                if (abs(e[l]) <= prec)
                  {	test_convergence= true;
                        break ;
                  }
                if (abs(q[l-1]) <= prec)
                  break ;
              }
          if (!test_convergence)
            {	// cancellation of e[l] if l>0
              c= 0.0;
              s= 1.0;
              long l1= l-1;
              for (i =l; i<k+1; i++)
                {	
                  f= s*e[i];
                  e[i]= c*e[i];
                  if (abs(f) <= prec)
                    break;
                  g= q[i];
                  h= pythag(f,g);
                  q[i]= h;
                  c= g/h;
                  s= -f/h;
                  for (j=0
                         ,  j_l1_offset = l1
                         ,  j_i_offset = i
                         ;
                       j < m;
                       j++
                         , j_l1_offset += n
                         , j_i_offset  += n
                       )
                    {
                      // y= uj[l1];
                      y = u[ j_l1_offset ];
                      
                      // z= uj[i];
                      z = u[ j_i_offset ];
                      
                      // uj[l1] =  y*c+(z*s);
                      u[ j_l1_offset ] =  y*c+(z*s);
                      
                      // uj[i] = -y*s+(z*c);
                      u[ j_i_offset ]  = -y*s+(z*c);
                    } 
                }	
            }
          // test f convergence
          z= q[k];
          if (l== k)
            {	//convergence
              if (z<0.0)
                {	//q[k] is made non-negative
                  q[k]= -z;
                  for (j=0,  j_k_offset = k; j < n; j++, j_k_offset += n)
                    {
                      // v[j][k] = -v[j][k];
                      v[ j_k_offset ] = -v[ j_k_offset ];
                    }
                }
              break;  //break out of iteration loop and move on to next k value
            }

          if (!(iteration < itmax-1))
            return false; // Error: no convergence.
          
          // shift from bottom 2x2 minor
          x= q[l];
          y= q[k-1];
          g= e[k-1];
          h= e[k];
          f= ((y-z)*(y+z)+(g-h)*(g+h))/(2.0*h*y);
          g= pythag(f,1.0);
          if (f < 0.0)
            f= ((x-z)*(x+z)+h*(y/(f-g)-h))/x;
          else
            f= ((x-z)*(x+z)+h*(y/(f+g)-h))/x;
          // next QR transformation
          c= 1.0;
          s= 1.0;
          for (i=l+1; i< k+1; i++)
            {	
              g= e[i];
              y= q[i];
              h= s*g;
              g= c*g;
              z= pythag(f,h);
              e[i-1]= z;
              c= f/z;
              s= h/z;
              f= x*c+g*s;
              g= -x*s+g*c;
              h= y*s;
              y= y*c;
              for (j=0,  j_i_offset = i;
                   j < n;
                   j++, j_i_offset += n
                   )
                {
                  auto j_im1_offset = j_i_offset - 1;
                  
                  // x= vj[i-1];
                  x = v[ j_im1_offset ];
                  
                  // z= vj[i];
                  z = v[ j_i_offset ];
                  
                  // vj[i-1] = x*c+z*s;
                  v[ j_im1_offset ] = x*c+z*s;
                  
                  // vj[i] = -x*s+z*c;
                  v[ j_i_offset ] = -x*s+z*c;
                }
              z= pythag(f,h);
              q[i-1]= z;
              c= f/z;
              s= h/z;
              f= c*g+s*y;
              x= -s*g+c*y;
              for (j=0,  j_i_offset = i;
                   j < m;
                   j++, j_i_offset += n)
                {
                  auto j_im1_offset = j_i_offset - 1;
                  
                  // y= uj[i-1];
                  y = u[ j_im1_offset ];
                  
                  // z= uj[i];
                  z = u[ j_i_offset ];

                  // uj[i-1] = y*c+z*s;
                  u[ j_im1_offset ] = y*c+z*s;
                  
                  // uj[i] = -y*s+z*c;
                  u[ j_i_offset ] = -y*s+z*c;
                }
            }
          e[l]= 0.0;
          e[k]= f;
          q[k]= x;
        } 
    }
  
  //vt= transpose(v)
  //return (u,q,vt)
  for (i=0;i<q.length; i++) 
    if (q[i] < prec) q[i] = 0.0;
	  
  //sort eigenvalues	
  for (i=0; i< n; i++)
    {	 
      //writeln(q)
      for (j=i-1; j >= 0; j--)
        {
          if (q[j] < q[i])
            {
              //  writeln(i,'-',j)
              c = q[j];
              q[j] = q[i];
              q[i] = c;
              // for(k=0;k<u.length;k++) { auto uk = u[ k ]; temp = uk[i]; uk[i] = uk[j]; uk[j] = temp; }
              for (k=0,  k_i_offset = i,  k_j_offset = j;
                   k < m;
                   k++, k_i_offset += n, k_j_offset += n)
                {
                  temp = u[ k_i_offset ];
                  u[ k_i_offset ] = u[ k_j_offset ];
                  u[ k_j_offset ] = temp;
                }

              // for(k=0;k<v.length;k++) { auto vk = v[ k ]; temp = vk[i]; vk[i] = vk[j]; vk[j] = temp; }
              for (k=0,  k_i_offset = i,  k_j_offset = j;
                   k < n;
                   k++, k_i_offset += n, k_j_offset += n)
                {
                  temp = v[ k_i_offset ];
                  v[ k_i_offset ] = v[ k_j_offset ];
                  v[ k_j_offset ] = temp;
                }
              
              //	   u.swapCols(i,j)
              //	   v.swapCols(i,j)
              i = j;
            }
        }	
    }

  diag_inplace( q, ret.S );

  transpose_inplace( ret.V, ret.VT );

  return true; // Converged
}





unittest  // --------------------------------------------------
{
  import std.stdio;
  import std.math : approxEqual;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  void check_consistency( in Matrix ma
                          , in SvdResult res
                          )
  {
    {
      immutable m = ma.nrow;
      immutable n = ma.ncol;
      assert( res.m == m );
      assert( res.n == n );
      assert( res.q.length == n );
      assert( res.e.length == n );
      assert( res.U.dim == [m, n] );
      assert( res.S.dim == [n, n] );
      assert( res.V.dim == [n, n] );
      assert( res.VT.dim == [n, n] );
      assert( approxEqual( res.VT.data, res.V.transpose.data, 1e-10, 1e-10 ) );
    }
    
    {
      
      const mb = res.U
        .dot
        (
         res.S
         .dot( res.V.transpose )
         );

      /*
      writeln();
      writeln("res.U ", res.U);
      writeln();
      writeln("res.U * diag_sigma", res.U.dot(res.S));
      writeln;
      writeln("ma: ", ma );
      writeln;
      writeln("mb: ", mb);
      */      
      assert( mb.approxEqual( ma, 1e-10, 1e-10 ) );
    }
  }

  {
    /*
      Test taken from http://stitchpanorama.sourceforge.net/Python/svd.py
      
      Itself taken from
      http://people.duke.edu/~hpgavin/SystemID/References/Golub+Reinsch-NM-1970.pdf
    */

    const ma = Matrix( [0, 5]
                       , [22.0, 10.0,  2.0,   3.0,  7.0,
                          14.0,  7.0, 10.0,   0.0,  8.0,
                          -1.0, 13.0, -1.0, -11.0,  3.0,
                          -3.0, -2.0, 13.0,  -2.0,  4.0,
                          9.0,  8.0,  1.0,  -2.0,  4.0,
                          9.0,  1.0, -7.0,   5.0, -1.0,
                          2.0, -6.0,  6.0,   5.0,  1.0,
                          4.0,  5.0,  0.0,  -2.0,  2.0
                          ]
                       );

    const res = svd( ma );
   
    assert( res.q.approxEqual( [sqrt( 1248.0 ), 20.0, sqrt( 384.0 ), 0.0, 0.0 ], 1e-10, 1e-10 ) ) ;
    
    check_consistency( ma, res );
  }

  
  {
    // Test copied from the lubeck library

    const ma = Matrix( [0, 4]
                       , [ 7.52,  -1.10,  -7.95,   1.08,
                           -0.76,  0.62,   9.34,  -7.10,
                           5.13,   6.62,  -5.66,   0.87,
                           -4.75,  8.52,   5.75,   5.30,
                           1.33,   4.91,  -5.49,  -3.52,
                           -2.40, -6.77,   2.34,   3.95
                           ]
                       );

    const res = svd( ma );

    check_consistency( ma, res );
  }

  
  writeln( "unittest passed: "~__FILE__ );
}
