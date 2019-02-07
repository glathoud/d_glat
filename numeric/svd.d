module d_glat_common.numeric.svd;


import d_glat_common.numeric.core;
import std.exception;
import std.math;

struct numeric_SvdResult
{
  double[][] U;
  double[][] S;
  double[][] V;
};


double[][] numeric_svd( in double[][] A )
// See also: ./pca_wrapper.d
{
  //Compute the thin SVD from G. H. Golub and C. Reinsch, Numer. Math. 14, 403-420 (1970)

  double temp;
  double prec= numeric_epsilon; //Math.pow(2,-52) // assumes double prec
  double tolerance= 1.e-64/prec;
  long itmax= 50;
  long c=0;
  long i=0;
  long j=0;
  long k=0;
  long l=0;
	
  auto u = numeric_clone(A);
  auto m= u.length;
	
  auto n= u[0].length;
	
  enforce( m >= n, "Need more rows than columns" );
  
  double[] e = new double[ n ];
  double[] q = new double[ n ];
  
  for (i=0; i<n; i++) e[i] = q[i] = 0.0;
  
  auto v = numeric_rep(n,n,0);
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
      e[i]= g;
      s= 0.0;
      l= i+1;
      for (j=i; j < m; j++) 
        s += (u[j][i]*u[j][i]);
      if (s <= tolerance)
        g= 0.0;
      else
        {	
          f= u[i][i];
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g-s;
          u[i][i]=f-g;
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
        s= s + u[i][j]*u[i][j];
      
      if (s <= tolerance)
        g= 0.0;
      else
        {	
          f= u[i][i+1];
          g= sqrt(s);
          if (f >= 0.0) g= -g;
          h= f*g - s;
          u[i][i+1] = f-g;
          for (j=l; j < n; j++) e[j]= u[i][j]/h;
          for (j=l; j < m; j++)
            {	
              s=0.0;
              for (k=l; k < n; k++) 
                s += (u[j][k]*u[i][k]);
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
      if (g != 0.0)
        {
          h= g*u[i][i+1];
          for (j=l; j < n; j++) 
            v[j][i]=u[i][j]/h;
          for (j=l; j < n; j++)
            {	
              s=0.0;
              for (k=l; k < n; k++) 
                s += u[i][k]*v[k][j];
              for (k=l; k < n; k++) 
                v[k][j]+=(s*v[k][i]);
            }	
        }
      for (j=l; j < n; j++)
        {
          v[i][j] = 0;
          v[j][i] = 0;
        }
      v[i][i] = 1;
      g= e[i];
      l= i;
    }
  
  // accumulation of left hand transformations
  for (i=n-1; i != -1; i+= -1)
    {	
      l= i+1;
      g= q[i];
      for (j=l; j < n; j++) 
        u[i][j] = 0;

      if (g != 0.0)
        {
          h= u[i][i]*g;
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
        for (j=i; j < m; j++) u[j][i] = 0;
      u[i][i] += 1;
    }
  
  // diagonalization of the bidiagonal form
  prec= prec*x;
  for (k=n-1; k != -1; k+= -1)
    {
      for (long iteration=0; iteration < itmax; iteration++)
        {	// test f splitting
          bool test_convergence = false
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
                      y= u[j][l1];
                      z= u[j][i];
                      u[j][l1] =  y*c+(z*s);
                      u[j][i] = -y*s+(z*c);
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
          if (iteration >= itmax-1)
            throw new Exception( 'Error: no convergence.' );

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
                  x= v[j][i-1];
                  z= v[j][i];
                  v[j][i-1] = x*c+z*s;
                  v[j][i] = -x*s+z*c;
                }
              z= pythag(f,h);
              q[i-1]= z;
              c= f/z;
              s= h/z;
              f= c*g+s*y;
              x= -s*g+c*y;
              for (j=0; j < m; j++)
                {
                  y= u[j][i-1];
                  z= u[j][i];
                  u[j][i-1] = y*c+z*s;
                  u[j][i] = -y*s+z*c;
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
    if (q[i] < prec) q[i] = 0;
	  
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
              for(k=0;k<u.length;k++) { temp = u[k][i]; u[k][i] = u[k][j]; u[k][j] = temp; }
              for(k=0;k<v.length;k++) { temp = v[k][i]; v[k][i] = v[k][j]; v[k][j] = temp; }
              //	   u.swapCols(i,j)
              //	   v.swapCols(i,j)
              i = j;
            }
        }	
    }

  numeric_SvdResult ret = {U:u,S:q,V:v};
  return ret;
}
