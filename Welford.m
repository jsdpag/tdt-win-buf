
classdef  Welford
% 
% Welford array class definition
% 
% This data type implements Welford's online algorithm, see:
%   
%   https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance
% 
% It is used to compute the running mean and variance of a stream of
% incoming data, such as might be the case when running an experiment.
% 
% Elements can be assigned or returned using standard MATLAB indexing, as
% with a numeric array. 
% 
% Each new sample of data is accumulated using the plus (+) operator. Data
% can be accumulated within an indexed sub-section of the Welford array.
% The accumulated data must be a numerical or logical array.
% 
% The current running sample mean is obtained from the 'avg' property.
% While the running sample variance is obtained through methods var, std,
% or sem.
% 
% If only logical values (or 1's and 0's) are accumulated then that data
% can be interpreted as the outcomes from a series of Bernoulli trials. In
% this case, the .avg property of the Welford array can be taken as the
% current estimated probability of a successful outcome. In this context,
% the outcome of var, std, and sem are invalid because they implicitly
% assume a normally (Gaussian) distributed random variable. Instead, use
% binpci to return the estimated binomial proportion confidence interval.
% It is up to the user to ensure that the proper input or function is
% called.
% 
% The following handle Welford arrays properly: size(), numel(), ndims(),
% cat() and horizontal/vertical concatenation syntax, permute(), reshape(),
% repmat(), isscalar(), isvector(), ismatrix(), isempty().
% 
% Example - Say that multi-variate random variable X with size N x 1 is
%   sampled under one of M conditions. A size N x M Welford array is needed
%   to maintain a running estimate of the sample mean and variance of X.
%   Create a new Welford array with no accumulated data by:
%   
%     w = Welford( N , M )
%   
%   The syntax is similar to zeros or ones.
%   
%   X is sampled under condition i. It is accumulated by the Welford array
%   using:
%   
%     w( : , i ) = w( : , i ) + X
%   
%   Retrieve the current sample mean under both conditions:
%   
%     w.avg
% 
%   Or under condition i:
%   
%     w.avg( : , i ) or w( : , i ).avg
%   
%   the former is expected to be more efficient for property access.
%   
%   Likewise, retrieve the number of samples accumulated by:
%   
%     w.count          % all conditions
%     w.count( : , i ) % condition i
%     w( : , i ).count % condition i
%   
%   Get the current estimated standard error of the mean for ...
%   
%     w.sem             % all conditions
%     sem( w )          % all conditions
%     w.sem( : , i )    % condition i
%     w( : , i ).sem    % condition i
%     sem( w( : , i ) ) % condition i
% 
% Written by Jackson Smith - April 2022 - Fries Lab (ESI Frankfurt)
%   
  
  %%% Internal data %%%
  
  properties ( Hidden = false , SetAccess = private , GetAccess = public )
    
    % Counts the number of samples added to each element.
    count  double
    
    % Running mean of each element, called avg to avoid overloading builtin.
    avg  double
    
    % Sum of squares of differences from the current mean.
    M2  double
    
  end % visible properties
  
  
  %%% Methods block - object specific %%%
  
  methods
    
    function  w = Welford( varargin )
    % 
    % w = Welford
    % w = Welford( n )
    % w = Welford( sz1 , ... szN )
    % w = Welford( sz )
    %
    % Constructor method, create a new instance of the Welford class. The
    % syntax is similar to zeros or ones. With no inputs, it returns a
    % scalar Welford array. A single scalar input returns an array of size
    % [ n , n ]. If 2 or more scalar arguments are given, then these are
    % the size of the array along each dimension i.e. szi is the length of
    % dimention i. If a single vector argument is given then the ith
    % element is the length of the ith dimension. The array is initialised
    % without any accumulated data.
    %
    % w = Welford( '-init' , icount , iavg , iM2 )
    % 
    % Create a Welford array but initialise the contents. Arguments
    % following the flat '-init' must all be double arrays and have the
    % same size.
    %
    
      % No input arguments, use default size
      if  nargin == 0
        
        varargin = { 1 , 1 } ;
      
      
      %--- w = Welford( '-init' , icount , iavg , iM2 ) ---%
      
      % First input is a string i.e. char row vector
      elseif  ischar( varargin{ 1 } ) && isrow( varargin{ 1 } )
        
        % Fetch flag
        flg = varargin{ 1 } ;
        
        % Check if this is the '-init' flag
        if  ~ strcmp( flg , '-init' )
          
          error( 'Unrecognised flag: ''%s''\nExpecting ''-init''' , flg )
        
        % We need exactly four input arguments, in total, including flag
        elseif  nargin ~= 4
          
          error( [ 'Four input args required for call ' , ...
            'Welford( ''-init'' , icount , iavg , iM2 )' ] )
          
        % All inputs must be double
        elseif  ~ all( cellfun( @( a ) isa( a , 'double' ) , ...
            varargin( 2 : end ) ) )
          
          error( 'icount, iavg, and iM2 must all be double arrays' )
          
        % All inputs must be same size
        elseif  ~ all( cellfun( ...
            @( a ) isequal( size( a ) , size( varargin{ 2 } ) ) , ...
              varargin( 3 : end ) ) )
          
          error( 'icount, iavg, and iM2 must all have the same size' )
            
        end % err check
        
        % Initialise
        [ w.count , w.avg , w.M2 ] = varargin{ 2 : end } ;
        
        % Done
        return
        
      
      %--- Error check other calls to Welford( ... ) ---%
      
      % First sweep of error checks, we need numeric input
      elseif  ~ all( cellfun( @isnumeric , varargin ) )
        
        error( 'Size inputs must be numeric.' )
        
      % There is more than one input argument, these must all be scalar
      elseif  nargin > 1  &&  ~ all( cellfun( @isscalar  , varargin ) )
             
        error( 'Size inputs sz1, ... szN must all must be scalar.' )
        
      % We reach this check only if nargin is 1. Make sure it is a vector.
      elseif  ~ isvector( varargin{ 1 } )
        
        error( 'Size argument sz must be a vector' )
        
      end % cell array error check
      
      % We know that we have scalar numeric values. Get them into a vector.
      sz = [ varargin{ : } ] ;
      
      % All values must be finite, no NaN or Inf
      if  ~ all( isfinite( sz ) )
        
        error( 'NaN and Inf not allowed.' )
        
      % Real values required, no complex numbers
      elseif  ~ isreal( sz )
        
        error( 'Size inputs must be real-valued (no complex).' )
        
      % Integer values required
      elseif  any( mod( sz , 1 ) )
        
        error( 'Size inputs must be integers.' )
        
      end % sz error check
      
      % Initialise empty Welford array
      w.count = zeros( sz ) ;
        w.avg = zeros( sz ) ;
         w.M2 = zeros( sz ) ;
      
    end % Welford
    
    
    function  v = var( w )
    % 
    % var( w )
    %
    % Return running sample variance from Welford array w. Output is double
    % array with size( w ) containing estimated variance for each element.
    % 
    
      v = w.M2  ./  ( w.count - 1 ) ;
      
    end % var
    
    
    function  s = std( w )
    % 
    % std( w )
    %
    % Return running sample standard deviation from Welford array w. Output
    % is double array with size( w ) containing estimated standard
    % deviation for each element.
    % 
    %
    
      s = sqrt( w.var ) ;
    
    end % std
    
    
    function  e = sem( w )
    % 
    % sem( w )
    % 
    % Computes standard error of the mean for Welford array w. Returns
    % double array of size( w ) containing SEM of each element.
    % 
      
      e = std( w ) ./ sqrt( w.count ) ;
      
    end % sem
    
    
    function  ci = binpci( w , p )
    % 
    % ci = binpci( w )
    % ci = binpci( w , p )
    % 
    % Computes the Binomial proportion confidence interval, assuming that
    % Welford array w has only been used to accumulate data consisting of
    % 1's (ones, successes) or 0's (zeros, failures). In other words, the
    % outcome of Bernoulli trials. In this case, w.avg contains the
    % estimated probability of a successful outcome. It is up to the user
    % to ensure that no other values are accumulated. Only the magnitude of
    % the confidence interval is returned. This must be added and
    % subtracted from w.avg to get the upper and lower confidence limits.
    % By default, the 95% confidence interval is returned (p = 0.95).
    % Provide the second, optional input argument p as a probability  value
    % (bounded between 0 and 1) in order to return a different confidence
    % interval e.g. call binpci( w , 0.99 ) to obtain the 99% confidence
    % interval
    % 
      
      % p not provided, use default
      if  nargin < 2 , p = 0.95 ; end
      
      % Error check p
      if  ~ isfloat( p ) || ~ isscalar( p ) || ~ isfinite( p ) || ...
          ~ isreal( p ) || p <= 0 || p >= 1
        
        error( [ 'p must be a scalar floating point, finite, ' , ...
          'real-valued number between 0 and 1' ] )
        
      end % err check
      
      % Guarantee p is double
      if  ~ isa( p , 'double' ) , p = double( p ) ; end
      
      % Calculate z-score associated with p-value p
      z = abs( norminv( ( 1 - p ) / 2 ) ) ;
      
      % Return confidence interval
      ci = z .* sqrt( w.avg .* ( 1 - w.avg ) ./ w.count ) ;
      
    end % binpci
    
     
    function  w = plus( a , b )
    % 
    % w + x
    % x + w
    %
    % Accumulates data sample x into existing Welford array w. x must be
    % numeric or logical and have the same size as w.
    %  
      
      %-- Input check --%
      
      % Assign meaningful names when operator has form:
      if      typechk( a , b ) , w = a ;  x = b ; % w + x
      elseif  typechk( b , a ) , w = b ;  x = a ; % x + w
      else
        error( 'Expects a Welford array and a numeric or logical array' )
      end
      
      % Same size?
      if  ~ isequal( size( w ) , size( x ) )
        
        error( 'Arguments must have the same size.' )
        
      end % size chk
      
      % Guarantee that x is double
      if  ~ isa( x , 'double' ) , x = double( x ) ; end
      
      
      %-- Welford algorithm: accumulate new sample --%
      
      % Increment the count by +1
      w.count = w.count + 1 ;
      
      % Difference of new sample vs running average
      dold = x - w.avg ;
      
      % Accumulate new sample into running average
      w.avg = w.avg  +  dold ./ w.count ;
      
      % Recalculate difference between new sample and running average
      dnew = x - w.avg ;
      
      % Accumulate sum of squares of differences
      w.M2 = w.M2  +  dold .* dnew ;
      
      %-- Sub-routine --%
      
      % Returns true if warg if a Wellford array, and if narg is numeric or
      % logical.
      % 
      function  out = typechk( warg , narg )
        
        out = isa( warg , 'Welford' )  &&  ...
          ( isnumeric( narg ) || islogical( narg ) ) ;
        
      end % typechk
    end % plus
    
    
    function  n = numArgumentsFromSubscript( ~ , ~ , ~ ) , n = 1 ; end
    
    function  ind = end( w , k , ~ ) , ind = size( w , k ) ; end
    
    
    function  varargout = subsref( w , s )
    
      % Default no error
      err = '' ;
      
      % Handle different types of indexing
      switch  s( 1 ).type
        
        % Return a subset of Welford array's internal data
        case  '()'
          
          % Copy Welford array
          r = w ;
          
          % Grab subsets of data
          r.count = builtin( 'subsref' , w.count , s( 1 ) ) ;
            r.avg = builtin( 'subsref' ,   w.avg , s( 1 ) ) ;
             r.M2 = builtin( 'subsref' ,    w.M2 , s( 1 ) ) ;
            
          % No nested indexing, no action except short circuit if statement
          if  numel( s ) == 1
            
          % Nested dot indexing of form w( index ).<name> where name is a
          % property or method
          elseif  numel( s ) == 2 && strcmp( s( 2 ).type , '.' )
            
            % Welford array r retrieves named property or method output and
            % assignes this to r
            r = r.( s( 2 ).subs ) ;
            
          % Invalid indexing
          else
            
            err = 'Deeply nested' ;
            
          end % nested indexind
          
          
        % No brace indexing defined for a Welford array
        case  '{}' , err = 'Brace' ;
          
        % Property access
        case   '.'
          
          % Fetch named property
          p = w.( s( 1 ).subs ) ;
          
          % Handle nested indexing
          switch  numel( s )
          
            % No nested indexing, simply return named property
            case  1 , r = p ;
            
            % Handle nested indexing of type w.property( index )
            case  2
              
              % Must be curved brace indexing operator
              if  strcmp( s( 2 ).type , '()' )
              
                r = builtin( 'subsref' , p , s( 2 ) ) ;
                
              % Not defined for anything else
              else
                
                err = [ 'w.' , s( 1 ).subs , ...
                  strrep( s( 2 ).type , '.' , '.<name>' ) ] ;
                
              end % handle nested index
                           
            % Unrecognised indexing structure
            otherwise , err = 'Deeply nested' ;
            
          end % nested indexing
          
        % This should never happen
        otherwise , error( 'Unknown indexing operator ''%s''' , s.type )
          
      end % index handling
      
      % Index type error detected
      if  ~ isempty( err )
        error( [ err , ' indexing is not supported for variables ' , ...
          'of this type.' ] )
      end
      
      % Return value
      varargout{ 1 } = r ;
      
    end % subsref
    
    function  w = subsasgn( w , s , varargin )
      
      % Default error
      err = '' ;
      
      % Point to right-hand argument, no comma-separated lists allowed
      arg = varargin{ 1 } ;
      
      % Handle indexing operators
      switch  s( 1 ).type
        
        % Only valid indexing for assignment
        case  '()'
          
          % This must be a Welford array
          if  ~ isa( arg , 'Welford' )
            error( 'Right-hand argument must be a Welford array.' )
          end
          
          % Assign subsets of data
          w.count = builtin( 'subsasgn' , w.count , s( 1 ) , arg.count ) ;
            w.avg = builtin( 'subsasgn' ,   w.avg , s( 1 ) , arg.avg   ) ;
             w.M2 = builtin( 'subsasgn' ,    w.M2 , s( 1 ) , arg.M2    ) ;
          
        % Brace indexing not defined
        case  '{}' , err = 'Brace' ;
          
        % Dot indexing necessary to assign property values
        case   '.'
          
          % SetAccess is supposed to be private! But MATLAB doesn't seem to
          % recognise this when overriding subsasgn.
          switch  s( 1 ).subs
            case  properties( 'Welford' )'
              error( '%s set access is private.' , s( 1 ).subs )
            otherwise
              error( 'Cannot set a method.' )
          end
          
        % We should never get here
        otherwise , error( 'Unknown indexing operator ''%s''' , s.type )
        
      end % indexing ops
      
      % Index type error detected
      if  ~ isempty( err )
        error( [ err , ' indexing is not supported for variables ' , ...
          'of this type.' ] )
      end
      
    end % subsasgn
    
    function  s =  size( w , varargin )
      s =  size( w.count , varargin{ : } ) ;
    end
    
    function  n = numel( w ) , n = numel( w.count ) ; end
    
    function  n = ndims( w ) , n = ndims( w.count ) ; end
    
    function  w = cat( dim , varargin )
      
      % All objects must be Welford arrays
      if  ~ all( cellfun( @( a ) isa( a , 'Welford' ) , varargin ) )
        error( 'Cannot concatenate a Welford array with any other type.' )
      end
      
      % Property names
      for  N = properties( 'Welford' )' , n = N{ 1 } ;
        
        % Point to named property of all input Welford arrays
        p.( n ) = cellfun( @( a ) a.( n ) , varargin , ...
          'UniformOutput' , false ) ;
        
        % Concatenate them together
        p.( n ) = cat( dim , p.( n ){ : } ) ;
        
      end % properties
      
      % Return a Welford array initialised with concatenated data
      w = Welford( '-init' , p.count , p.avg , p.M2 ) ;
      
    end % cat
    
    function  w = horzcat( varargin ) , w = cat( 2 , varargin{ : } ) ; end
    
    function  w = vertcat( varargin ) , w = cat( 1 , varargin{ : } ) ; end
    
    function  w = permute( w , d )
      w.count = permute( w.count , d ) ;
        w.avg = permute( w.avg , d ) ;
         w.M2 = permute( w.M2 , d ) ;
    end
    
    function  w = reshape( w , varargin )
      w.count = reshape( w.count , varargin{ : } ) ;
        w.avg = reshape( w.avg , varargin{ : } ) ;
         w.M2 = reshape( w.M2 , varargin{ : } ) ;
    end
    
    function  w = repmat( w , varargin )
      w.count = repmat( w.count , varargin{ : } ) ;
        w.avg = repmat( w.avg , varargin{ : } ) ;
         w.M2 = repmat( w.M2 , varargin{ : } ) ;
    end
    
    function  s = isscalar( w ) , s = isscalar( w.count ) ; end
    function  v = isvector( w ) , v = isvector( w.count ) ; end
    function  m = ismatrix( w ) , m = ismatrix( w.count ) ; end
    function  e = isempty ( w ) , e = isempty ( w.count ) ; end
    
  end % methods - object specific
    
  
end % classdef Welford

