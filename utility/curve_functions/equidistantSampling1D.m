function [xloc, ssloc] = equidistantSampling1D(xvals, ss, nsamples, method)
%EQUIDISTANTSAMPLING(ss)
% Given a series of values ss 
% 
% Parameters
% ----------
% xvals : N x 1 float or int array
%   the dimension to resample in order to achieve uniform ds = diff(ssloc)
% ss : N x 1 float array
%   pathlength at each index site. For ex, (0, 1.2, 2.4, ...) if ds = 1.2 
%   and xvals are evenly spaced
% nsamples : int
%   Number of points along the curve to sample
% method : str (default='linear')
%   How to interpolate
% 
% Returns
% -------
% xloc : N x 1 float
%   Locations in xvals of where
%
% Example Usage
% -------------
% nsamples = 100 ; method = 'linear'; 
% xvals = linspace(0, 1, 100) ;
% ss = xvals.^2 ;
% [xloc, ssloc] = equidistantSampling1D(xvals, ss, nsamples, method)
% plot(xvals, ss); hold on;
% plot(xloc, ssloc, 'o')
% 
% 
% NPMitchell 2020

if nargin < 4
    method = 'linear' ;
end

samplingss = linspace(0, max(ss), nsamples) ;
if strcmpi(method, 'linear')
    xloc = interp1(ss, xvals, samplingss, method) ;
    if nargout > 1
        ssloc = interp1(xvals, ss, xloc, method) ;
    end
else
    error('code for this method here')
end


