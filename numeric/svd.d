module d_glat_common.numeric.svd;


import d_glat_common.numeric.core;
import std.exception;
import std.math;

struct SvdResult
{
  double[][] U;
  double[]   S;
  double[][] V;
  double[][] VT;
};


SvdResult svd( in double[][] A )
// See also: ./pca_wrapper.d
{
  //Compute the thin SVD from G. H. Golub and C. Reinsch, Numer. Math. 14, 403-420 (1970)

  double temp;
  double prec= numeric_epsilon; //Math.pow(2,-52) // assumes double prec
  double tolerance= 1e-64/prec;
  long itmax= 50;
  double c=0.0;
  long i=0;
  long j=0;
  long k=0;
  long l=0;
	
  auto u = clone(A);
  immutable m= u.length;
	
  immutable n= u[0].length;
	
  enforce( m >= n, "Need more rows than columns" );
  
  double[] e = new double[ n ];
  double[] q = new double[ n ];
  
  for (i=0; i<n; i++) e[i] = q[i] = 0.0;
  
  auto v = rep(n,n,0);
  //	v.zero();
	
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
	
  for (i=0; i < n; i++)
    {
      auto ui = u[ i ];
      
      e[i]= g;
      s= 0.0;
      l= i+1;
      for (j=i; j < m; j++) 
        s += (u[j][i]*u[j][i]);
      if (s <= tolerance)
        g= 0.0;
      else
        {	
          f= ui[i];
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g-s;
          ui[i]=f-g;
          for (j=l; j < n; j++)
            {
              s= 0.0;
              for (k=i; k < m; k++) 
                s += u[k][i]*u[k][j];

              f= s/h;

              for (k=i; k < m; k++) 
                u[k][j]+=f*u[k][i];
            }
        }
      q[i]= g;
      s= 0.0;
      for (j=l; j < n; j++) 
        s= s + ui[j]*ui[j];
      
      if (s <= tolerance)
        g= 0.0;
      else
        {	
          f= ui[i+1];
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g - s;
          ui[i+1] = f-g;
          for (j=l; j < n; j++) e[j]= ui[j]/h;
          for (j=l; j < m; j++)
            {	
              s=0.0;
              for (k=l; k < n; k++) 
                s += (u[j][k]*ui[k]);
              for (k=l; k < n; k++) 
                u[j][k]+=s*e[k];
            }	
        }
      y= abs(q[i])+abs(e[i]);
      if (y>x) 
        x=y;
    }
  
  // accumulation of right hand gtransformations
  for (i=n-1; i != -1; i+= -1)
    {
      auto ui = u[ i ];
      
      if (g != 0.0)
        {
          h= g*ui[i+1];
          for (j=l; j < n; j++) 
            v[j][i]=ui[j]/h;
          for (j=l; j < n; j++)
            {	
              s=0.0;
              for (k=l; k < n; k++) 
                s += ui[k]*v[k][j];

              for (k=l; k < n; k++) 
                v[k][j]+=(s*v[k][i]);
            }	
        }

      auto vi = v[ i ];
      
      for (j=l; j < n; j++)
        {
          vi[j] = 0.0;
          v[j][i] = 0.0;
        }
      vi[i] = 1.0;
      g= e[i];
      l= i;
    }
  
  // accumulation of left hand transformations
  for (i=n-1; i != -1; i+= -1)
    {	
      auto ui = u[ i ];

      l= i+1;
      g= q[i];
      for (j=l; j < n; j++) 
        ui[j] = 0.0;

      if (g != 0.0)
        {
          h= ui[i]*g;
          for (j=l; j < n; j++)
            {
              s=0.0;
              for (k=l; k < m; k++) s += u[k][i]*u[k][j];
              f= s/h;
              for (k=i; k < m; k++) u[k][j]+=f*u[k][i];
            }
          for (j=i; j < m; j++) u[j][i] = u[j][i]/g;
        }
      else
        for (j=i; j < m; j++) u[j][i] = 0.0;
      ui[i] += 1.0;
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
                  for (j=0; j < m; j++)
                    {
                      auto uj = u[ j ];
                      
                      y= uj[l1];
                      z= uj[i];
                      uj[l1] =  y*c+(z*s);
                      uj[i] = -y*s+(z*c);
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
                  for (j=0; j < n; j++)
                    v[j][k] = -v[j][k];
                }
              break;  //break out of iteration loop and move on to next k value
            }

          enforce( iteration < itmax-1
                   , "Error: no convergence."
                   );
          
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
              for (j=0; j < n; j++)
                {	
                  auto vj = v[ j ];
                  
                  x= vj[i-1];
                  z= vj[i];
                  vj[i-1] = x*c+z*s;
                  vj[i] = -x*s+z*c;
                }
              z= pythag(f,h);
              q[i-1]= z;
              c= f/z;
              s= h/z;
              f= c*g+s*y;
              x= -s*g+c*y;
              for (j=0; j < m; j++)
                {
                  auto uj = u[ j ];
                  
                  y= uj[i-1];
                  z= uj[i];
                  uj[i-1] = y*c+z*s;
                  uj[i] = -y*s+z*c;
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
              for(k=0;k<u.length;k++) { auto uk = u[ k ]; temp = uk[i]; uk[i] = uk[j]; uk[j] = temp; }
              for(k=0;k<v.length;k++) { auto vk = v[ k ]; temp = vk[i]; vk[i] = vk[j]; vk[j] = temp; }
              //	   u.swapCols(i,j)
              //	   v.swapCols(i,j)
              i = j;
            }
        }	
    }

  SvdResult ret = {U:u,S:q,V:v,VT:v.transpose};
  return ret;
}





unittest  // --------------------------------------------------
{
  import std.stdio;
  import std.math : approxEqual;
  
  writeln;
  writeln( "unittest starts: "~__FILE__ );

  void check_consistency( in double[][] ma
                          , in SvdResult res
                          )
  {
    {
      assert( approxEqual( res.VT, res.V.transpose, 1e-10, 1e-10 ) );
    }
    
    {
      writeln();
      writeln("res.U ", res.U);
      writeln();
      writeln("res.U * diag_sigma", res.U.dot(res.S.diag));

      const mb = res.U
        .dot
        (
         res.S.diag
         .dot( res.V.transpose )
         );
      assert( approxEqual( mb, ma, 1e-10, 1e-10 ) );
    }
  }

  {
    /*
      Test taken from http://stitchpanorama.sourceforge.net/Python/svd.py
      
      Itself taken from
      http://people.duke.edu/~hpgavin/SystemID/References/Golub+Reinsch-NM-1970.pdf
    */

    immutable ma = [[22.0, 10.0,  2.0,   3.0,  7.0],
                    [14.0,  7.0, 10.0,   0.0,  8.0],
                    [-1.0, 13.0, -1.0, -11.0,  3.0],
                    [-3.0, -2.0, 13.0,  -2.0,  4.0],
                    [ 9.0,  8.0,  1.0,  -2.0,  4.0],
                    [ 9.0,  1.0, -7.0,   5.0, -1.0],
                    [ 2.0, -6.0,  6.0,   5.0,  1.0],
                    [ 4.0,  5.0,  0.0,  -2.0,  2.0]
                    ];

    const res = svd( ma );
   
    assert( res.S.approxEqual( [ sqrt( 1248.0 ), 20.0, sqrt( 384.0 ), 0.0, 0.0 ], 1e-10, 1e-10 ) );
    
    check_consistency( ma, res );
  }

  
  {
    // Test copied from the lubeck library

    immutable ma = [
                   [  7.52,  -1.10,  -7.95,   1.08 ],
                   [ -0.76,   0.62,   9.34,  -7.10 ],
                   [  5.13,   6.62,  -5.66,   0.87 ],
                   [ -4.75,   8.52,   5.75,   5.30 ],
                   [  1.33,   4.91,  -5.49,  -3.52 ],
                   [ -2.40,  -6.77,   2.34,   3.95 ]
                   ];

    const res = svd( ma );

    check_consistency( ma, res );
  }

  
  writeln( "unittest passed: "~__FILE__ );
}
