function [adIDx, pdIDx] = aux_adjust_dIDx(mesh, cylmesh, t, dpFile,...
    ADBase, PDBase, cylinderMeshCleanDir, ...
    cylinderMeshCleanBase, outadIDxfn, outpdIDxfn, timePoints,...
    followPtsInTime) 
%[adIDx, pdIDx] = aux_adjust_dIDx(mesh, cylmesh, t, dpFile, ...
%       ADBase, PDBase, cylinderMeshCleanDir, cylinderMeshCleanBase, ...
%       outadIDxfn, outpdIDxfn, timePoints, followPtsInTime) 
%
% Auxilliary function for adjusting adIDx and pdIDx in
% Generate_Axisymmetric_Pullbacks_Orbifold.m script
% 
% The anterior and posterior "dorsal" points (ie ad and pd) are where the
% cutpath of the cylinderCutMesh starts and ends, respectively.
% 
% Parameters
% ----------
% mesh: cylinder cut mesh with Cleaned Ears (cleanCylCutMesh)
% cylmesh: cylinder cut mesh before ear cleaning
% t :
% dpFile : 
% ADBase :
% PDBase : 
% cylinderMeshCleanDir : char
% cylinderMeshCleanBase : char
% outadIDxfn : char
% outpdIDxfn : char
% timePoints :
% followPtsInTime : bool
%   pointmatch the previous timepoint's a/p dorsal point to the
%   nearest a/p boundary vertex rather than pointmatching the current
%   timepoint's a/p endcap dorsal point to the cleaned mesh's
%   posterior boundary.
%
% Returns
% -------
% adIDx : anterior dorsal point for cutting the anterior endcap 
% pdIDx : posteriod dorsal point for cutting the posterior endcap 

% Load the AD/PD vertex IDs
disp('Loading ADPD vertex IDs...')
if (t == timePoints(1)) || ~followPtsInTime
    disp(['reading h5 file: ' dpFile])
    adIDx = h5read( dpFile, sprintf( ADBase, t ) );
    pdIDx = h5read( dpFile, sprintf( PDBase, t ) );

    ad3D = cylmesh.v( adIDx, : );
    pd3D = cylmesh.v( pdIDx, : );
else
    currtidx = find(timePoints == t) ;
    prevtp = timePoints(currtidx - 1) ;
    % Load previous mesh and previous adIDx, pdIDx
    prevcylmeshfn = fullfile(cylinderMeshCleanDir, ...
        sprintf( cylinderMeshCleanBase, prevtp )) ;
    prevmesh = read_ply_mod( prevcylmeshfn ); 
    prevadIDx = h5read(outadIDxfn, ['/' sprintf('%06d', prevtp) ]) ;
    % read previous pdIDx with new indices
    prevpdIDx = h5read(outpdIDxfn, ['/' sprintf('%06d', prevtp) ]) ;
    ad3D = prevmesh.v(prevadIDx, :) ;
    pd3D = prevmesh.v(prevpdIDx, :) ;
end

% Haibei had added that we never follow the posterior in time. But we
% reverted to using followADandPDPtsInTime / followPtsInTime
% pdIDx = h5read( dpFile, sprintf( PDBase, t ) );
% pd3D = cylmesh.v( pdIDx, : );


trngln = triangulation(mesh.f, mesh.v) ;
boundary = trngln.freeBoundary ;
adIDx = boundary(pointMatch( ad3D, mesh.v(boundary(:, 1), :) ), 1);
pdIDx = boundary(pointMatch( pd3D, mesh.v(boundary(:, 1), :) ), 1);


