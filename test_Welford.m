
% 
% Run a simple set of tests to see if the Welford array functions properly
% 

%% Initialisation

% Welford array size vector
sz = [ 2 , 1 ] ;

  % Product of dimensions
  M = prod( sz ) ;

% Expected value and standard deviation, the ground truth
E = [ 0 ; +0.5 ] ;
S = [ 0.5 ; 1 ] ;

  % Check
  if  ~ isequal( sz , size( E ) ) || ~ isequal( sz , size( S ) )
    error( 'sz and E or S size mismatch' )
  end

% Number of trials to generate
N = 1e3 ;


%% Run simulation

% Generate data, trials per variable
X = randn( [ N , M ] ) .* reshape( S , [ 1 , M ] )  +  ...
  reshape( E , [ 1 , M ] ) ;

% Cumulative average across all data
c.avg = cumsum( X , 1 ) ./ ( 1 : N )' ;

% Cumulative standard deviation ...
c.std = zeros( [ N , M ] ) ;

% ... across all data
for  i = 1 : N
  c.std( i , : ) = std( X( 1 : i , : ) , 0 , 1 ) ;
end

% Create freshly initialised Welford array
w = Welford( sz ) ;

% Allocate current running average and standard deviation
r.avg = zeros( [ N , M ] ) ;
r.std = zeros( [ N , M ] ) ;

% Simulate trial-by-trial sampling of data
for  i = 1 : N , x = reshape( X( i , : ) , sz ) ;
  
  % Accumulate data
  w = w + x ;
  
  % Remember current estimate of mean and variance
  r.avg( i , : ) = reshape( w.avg , [ 1 , M ] ) ;
  r.std( i , : ) = reshape( w.std , [ 1 , M ] ) ;
  
end % sim


%% Check result

x = ( 1 : N )' ;

% Data types
for  F = { 'avg' , 'std' } , f = F{ 1 } ;
  figure
  plot( x , c.( f ) , 'LineWidth' , 4 )
  hold on
  plot( x , r.( f ) , 'k' , 'Linewidth' , 0.5 )
  set( gca , 'XScale' , 'log' )
  xlabel( 'Trials' )
  ylabel( f )
end
