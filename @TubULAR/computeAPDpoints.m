function [apts_sm, ppts_sm, dpt] = computeAPDpoints(tubi, opts)
%[apts_sm, ppts_sm, dpt] = COMPUTEAPDPOINTS(opts)
% Compute the anterior, posterior, and dorsal points either from:
%   (1) Clicking on the points on the mesh from t=t0
%   (2) moments of inertia of the mesh surface, identifying the endpoints
%       near the long axis of the object at t=t0. (autoAP = true)
%   (3) iLastik training for CENTERLINE computation.  (opts.use_iLastik=true)
%       Note that these are allowed to be different than the
%       APD points for ALIGNMENT computation. Here, we do not require any
%       dorsal point to be trained, as that was defined in the previous
%       step. However, it is useful to have A and P be separable from the
%       previous step.
%       For example, the posterior point
%       might be a point which does NOT form an AP axis  with the 
%       anteriormost point, as in the illustration of the midgut below.
%       To use this option, set opts.use_iLastik=true and by default the
%       script looks for iLastik files called
%       <<fn>>_Probabilities_apcenterline.h5.
%   (4) Directly supplying a custom set of anterior and posterior points
%       for each time point
% 
%         Posterior (distal) pt for centerline
%        _x_         Dorsal pt
%       /  /     ___x_
%      /  /    /      \    
%     /  /____/        \   Anterior (proximal) pt for both centerline and for defining APDV axes
%    |  x P for APDV    | x
%     \________________/
%    (ventral here, unlabeled)
%
% The default behavior is to use iLastik training if found, unless 
% opts.use_iLastik is set to false. If use_iLastik is false or no iLastik 
% output is found, the default is to have the user click on the points.
% If opts.autoAP == true, then we automatically find A and P positions by
% simply point matching from line intersections onto the mesh.
%
%
% Parameters
% ----------
% opts : struct with fields
%   - use_iLastik : default=true if training h5s are present on disk
%   - timePoints : timepoints for which to extract APD points
%   - dorsal_thres : float between 0 and 1, threshold for COM extraction
%   - anteriorChannel : int, which channel of training to use if training
%                       is used for extracting COM from probability cloud
%   - posteriorChannel : int, which channel of training to use if training
%                       is used for extracting COM from probability cloud
%   - dorsalChannel : int, which channel of training to use if training
%                       is used for extracting COM from probability cloud
%   - overwrite : bool, overwrite previous results on disk
%   - preview_com : bool, inspect the centers of mass extraction
%   - axorder : length 3 int array, permutation of axes if needed
%   - smwindow : float or int (optional, default=30)
%       number of timepoints over which we smooth
%   - preview : bool (optional, default=false)
%   - autoAP : bool whether or not to extract A-P points using an automatic
%           method using the moments of inertia of the mesh
%           (optional, default=false)
%   - custom_apts : a custom set of 3D anterior points
%           (optional, default=[])
%   - custom_ppts : a custom set of 3D posterior points
%           (optional, default=[])
%   - thres : threshold for extracting a connected component of high
%   probability to define A and P and D points
%       
%
% OUTPUTS
% -------
% apdv_pts_for_centerline.h5 (rawapdvname, tubi.fileName.apdv)
%   Raw points (centers of mass if training-based) for A, P, and D in 
%   subsampled pixels, in probability data space coordinate system. (note
%   this is downsampled by ssfactor)
%   Saved to fullfile(meshDir, 'centerline/apdv_pts_for_centerline.h5')
% tubi.fileName.dpt
%   txt file with dorsal COM for APDV definition
% rawapdvmatname=fullfile(tubi.dir.cntrline, 'apdv_pts_for_centerline.mat')
% 
%
% NPMitchell 2020

timePoints = tubi.xp.fileMeta.timePoints ;
apdvoutdir = tubi.dir.cntrline ;
meshDir = tubi.dir.mesh ;
swapAP = false ;
thres = 0.5 ;
% axorder = tubi.data.axisOrder ; % NOTE: axisorder for texture_axis_order
                                % invoked upon loading IV into tubi.currentData.IV
ilastikOutputAxisOrder = tubi.data.ilastikOutputAxisOrder ;

if isfield(opts, 'aProbFileName')
    aProbFileName = opts.aProbFileName ;
else
    aProbFileName = tubi.fullFileBase.apCenterlineProb ;
end
if isfield(opts, 'pProbFileName')
    pProbFileName = opts.pProbFileName ;
else
    pProbFileName = tubi.fullFileBase.apCenterlineProb ;
end
if isfield(opts, 'ilastikOutputAxisOrder')
    ilastikOutputAxisOrder = opts.ilastikOutputAxisOrder ;
end
if (isfield(opts, 'custom_apts') && isfield(opts, 'custom_ppts'))
    useCustomPts = ~isempty(opts.custom_apts) && ...
        ~isempty(opts.custom_ppts);
    if useCustomPts
        useCustomPts = isequal(size(opts.custom_apts), ...
            size(opts.custom_ppts)) && ...
            (size(opts.custom_apts,1) == length(timePoints)) && ...
            (size(opts.custom_apts,2) == 3);
    end
    if ~useCustomPts
        disp('Invalid custom input points supplied. Ignoring input');
    end
else
    useCustomPts = false;
end
if useCustomPts
    use_iLastik = false;
elseif isfield(opts, 'use_iLastik')
    use_iLastik = opts.use_iLastik ;
else
    use_iLastik = exist(aProbFileName, 'file') && ...
        exist(pProbFileName, 'file') ;
    if ~use_iLastik
        disp(['No ilastik training specifically for centerline computation', ...
        'was found, so define the centerline endpoints based on the mesh elongation axis'])
    end
end
if ((~use_iLastik) && (~useCustomPts))
    if isfield(opts, 'autoAP')
        autoAP = opts.autoAP ; % would you like to find automatic points for endcaps A and P?
    else
        autoAP = false ; % instead by default, click on the A and P points at t=t0
    end
end
if isfield(opts, 'swapAP')
    swapAP = opts.swapAP ;
elseif isfield(opts, 'flipAP')
    swapAP = opts.flipAP ;
end
if isfield(opts, 'thres')
    thres = opts.thres ;
end

% Default options
overwrite = false ; 
preview_com = false ;

% Unpack opts
if isfield(opts, 'anteriorChannel')
    anteriorChannel = opts.anteriorChannel ;
else
    anteriorChannel = 1 ;
end
if isfield(opts, 'anteriorChannel')
    posteriorChannel = opts.posteriorChannel ;
else
    posteriorChannel = 2 ;
end
if isfield(opts, 'overwrite')
    overwrite = opts.overwrite ;
end
if isfield(opts, 'preview_com')
    preview_com = opts.preview_com ;
end

% Default valued options
smwindow = 30 ;
if isfield(opts, 'smwindow')
    smwindow = opts.smwindow ;
end

rawapdvname = tubi.fileName.apdv ;
rawapdvmatname = fullfile(apdvoutdir, 'apdv_pts_for_centerline.mat') ;
preview = false ;
if isfield(opts, 'preview')
    preview = opts.preview ;
end


%% Iterate through each mesh to compute apts(t) and ppt(t). Prepare file.
apts = zeros(length(timePoints), 3) ;
ppts = zeros(length(timePoints), 3) ;
load_from_disk = false ;
if exist(tubi.fileName.apdv, 'file') && ~overwrite
    load_from_disk = true ;
    try
        h5create(tubi.fileName.apdv, '/apts_sm', size(apts)) ;
        load_from_disk = false ;
    catch
        try
            apts_sm = h5read(tubi.fileName.apdv, '/apts_sm') ;
            apts = h5read(tubi.fileName.apdv, '/apts') ;
            disp('apts_sm already exists')
        catch
            load_from_disk = false;
        end
        if load_from_disk
            if size(apts, 1) ~= length(tubi.xp.fileMeta.timePoints)
                disp(['#timepoints = ' num2str(length(tubi.xp.fileMeta.timePoints)) ])
                disp(['#timepoints on disk = ', num2str(size(apts, 1))])
                disp(['Must first rename ' tubi.fileName.apdv ' to overwrite with different number of timepoints: moving file.'])
                movefile(tubi.fileName.apdv, [tubi.fileName.apdv '_backup'])
                load_from_disk = false ;
            end
        end
    end
    try
        h5create(tubi.fileName.apdv, '/ppts_sm', size(ppts)) ;
        load_from_disk = false ;
    catch
        try
            ppts_sm = h5read(tubi.fileName.apdv, '/ppts_sm') ;
            ppts = h5read(tubi.fileName.apdv, '/ppts') ;
            disp('ppts_sm already exists')
        catch
            load_from_disk = false;
        end
        
        if load_from_disk
            if size(ppts, 1) ~= length(tubi.xp.fileMeta.timePoints) 
                disp(['Must first rename ' tubi.fileName.apdv ' to overwrite with different number of timepoints: moving file.'])
                movefile(tubi.fileName.apdv, [tubi.fileName.apdv '_backup'])
                load_from_disk = false ;
            end
        end
    end
end
if ~load_from_disk
    disp('apts and/or ppts not already saved on disk or overwrite==True. Compute them')
end

disp(['Load from disk? =>', num2str(load_from_disk)])

%% Compute smoothed apts and ppts if not loaded from disk -- RAW XYZ coords
if ~load_from_disk || overwrite
    
    
    if useCustomPts
        % Use a user supplied set of anterior/posterior points
        apts = opts.custom_apts / tubi.ssfactor;
        ppts = opts.custom_ppts / tubi.ssfactor;
        
        
    elseif use_iLastik
        % Compute raw apts and ppts if not loaded from disk -- RAW XYZ coords
        bad_size = false ;
        if exist(rawapdvmatname, 'file') && ~overwrite
            % load raw data from .mat
            load(rawapdvmatname, 'apts', 'ppts')
            bad_size = (size(apts, 1) ~= length(tubi.xp.fileMeta.timePoints)) ; 
        end

        if ~exist(rawapdvmatname, 'file') || overwrite || bad_size
            for tidx = 1:length(timePoints)
                tt = timePoints(tidx) ;
                %% Load the AP axis determination
                msg = ['Computing apts, ppts for ' num2str(tt) ] ;
                disp(msg)
                % load the probabilities for anterior posterior dorsal
                afn = replace(aProbFileName, tubi.timeStampStringSpec, num2str(tt, tubi.timeStampStringSpec));
                pfn = replace(pProbFileName, tubi.timeStampStringSpec, num2str(tt, tubi.timeStampStringSpec));
                
                % Old version (no good on Windows)
                % afn = sprintf(aProbFileName, tt);
                % pfn = sprintf(pProbFileName, tt);

                disp(['Reading ', afn])
                adatM = h5read(afn, '/exported_data');
                if ~strcmp(afn, pfn)
                    disp(['Reading ' pfn])
                    pdatM = h5read(pfn, '/exported_data') ;
                else
                    pdatM = adatM ;
                end

                % Load the training for anterior and posterior positions
                channelAxis = strfind(ilastikOutputAxisOrder, 'c') ;
                if channelAxis == 1
                    adat = squeeze(adatM(anteriorChannel,:,:,:)) ;
                    pdat = squeeze(pdatM(posteriorChannel,:,:,:)) ;
                elseif channelAxis == 2 
                    adat = squeeze(adatM(:, anteriorChannel,:,:)) ;
                    pdat = squeeze(pdatM(:, posteriorChannel,:,:)) ;
                elseif channelAxis == 3
                    adat = squeeze(adatM(:,:,anteriorChannel,:)) ;
                    pdat = squeeze(pdatM(:,:,posteriorChannel,:)) ;
                elseif channelAxis == 4 
                    adat = squeeze(adatM(:,:,:, anteriorChannel)) ;
                    pdat = squeeze(pdatM(:,:,:, posteriorChannel)) ;
                else
                    error(['Expected 4D probabilities data, and was ' ...
                        num2str(length(size(ddatM))) 'D, or failed to recognize ilastikOutputAxisOrder'])
                end

                disp(['Extracted adat and pdat of size [' num2str(size(adat)) ']'])
        
                xyzstring = erase(lower(ilastikOutputAxisOrder), 'c') ;
                xpos = strfind(xyzstring, 'x') ;
                ypos = strfind(xyzstring, 'y') ;
                zpos = strfind(xyzstring, 'z') ;
                disp(['Permuting adat and pdat as [' ...
                    num2str(xpos) ',' num2str(ypos) ',' num2str(zpos) ']'])
                adat = permute(adat, [xpos, ypos, zpos]) ;
                pdat = permute(pdat, [xpos, ypos, zpos]) ;
                
                % if contains(lower(ilastikOutputAxisOrder), 'xyz')
                %     disp('no permutation necessary')
                %     % adat = permute(adat, [1,2,3]);
                % elseif contains(lower(ilastikOutputAxisOrder), 'yxz')
                %     disp('permuting yxz')
                %     adat = permute(adat, [2,1,3]);
                %     pdat = permute(pdat, [2,1,3]);
                % elseif contains(lower(ilastikOutputAxisOrder), 'zyx')
                %     disp('permuting zyx')
                %     adat = permute(adat, [3,2,1]);
                %     pdat = permute(pdat, [3,2,1]);
                % elseif contains(lower(ilastikOutputAxisOrder), 'yzx')
                %     disp('permuting zyx')
                %     adat = permute(adat, [2,3,1]);
                %     pdat = permute(pdat, [2,3,1]);
                % else
                %     error('unrecognized permutation in ilastikOutputAxisOrder')
                % end

                % define axis order: 
                % if 1, 2, 3: axes will be yxz
                % if 1, 3, 2: axes will be yzx
                % if 2, 1, 3: axes will be xyz (ie first second third axes, ie --> 
                % so that bright spot at im(1,2,3) gives com=[1,2,3]

                % Note that axisOrder is applying upon invoking getCurrentData()
                % adat = permute(adat, axorder) ;
                % pdat = permute(pdat, axorder) ;


                % if preview
                %     for xid = 1:1:size(adat, 1)
                %         imagesc(squeeze(adat(xid, :,:))) ;
                %         cb = colorbar ;
                %         title(['x = ' num2str(xid)])
                %         pause(0.01)
                %     end
                % end



                options.check = preview_com ;
                disp('Extracting acom from probability h5 data')
                options.color = 'red' ;
                acom = com_region(adat, thres, options) ;
                
                disp('Extracting pcom from probability h5 data')
                options.color = 'blue' ;
                pcom = com_region(pdat, thres, options) ;
                clearvars options
                % [~, acom] = match_training_to_vertex(adat, thres, vertices, options) ;
                % [~, pcom] = match_training_to_vertex(pdat, thres, vertices, options) ;
                apts(tidx, :) = acom ;
                ppts(tidx, :) = pcom ;
                if preview
                    disp('acom = ')
                    apts(tidx, :)
                    disp('pcom = ')
                    ppts(tidx, :)

                    clf
                    meshfn = sprintf(tubi.fullFileBase.mesh, tt) ;
                    mesh = read_ply_mod(meshfn) ;
                    for ii = 1:3
                        subplot(1, 3, ii)
                        trisurf(triangulation(mesh.f, mesh.v), 'edgecolor', 'none', 'facealpha', 0.1)
                        hold on;
                        plot3(acom(1) * tubi.ssfactor, acom(2) * tubi.ssfactor, acom(3) * tubi.ssfactor, 'o')
                        plot3(pcom(1) * tubi.ssfactor, pcom(2) * tubi.ssfactor, pcom(3) * tubi.ssfactor, 'o')
                        axis equal
                        if ii == 1
                            view(0, 90)
                        elseif ii == 2
                            view(90, 0)
                        else
                            view(180, 0)
                        end
                    end
                    sgtitle(['t = ' num2str(tt)])
                    pause(0.1)
                end

                % PLOT APD points on mesh
                if tidx == 1
                    % load current mesh & plot the dorsal dot
                    clf
                    try
                        dpt = dlmread(tubi.fileName.dpt) ;
                    catch
                        error('Could not load dorsal COM: run tubi.computeAPDVCoords() first')
                    end
                    for ii = 1:3
                        subplot(1, 3, ii)
                        meshfn = replace(tubi.fullFileBase.mesh, ...
                            tubi.timeStampStringSpec, num2str(tt, tubi.timeStampStringSpec)) ;
                        mesh = read_ply_mod(meshfn) ;
                        trisurf(triangulation(mesh.f, mesh.v), 'edgecolor', 'none', 'facealpha', 0.1)
                        hold on;
                        plot3(acom(1) * tubi.ssfactor, acom(2) * tubi.ssfactor, acom(3) * tubi.ssfactor, 'o')
                        plot3(pcom(1) * tubi.ssfactor, pcom(2) * tubi.ssfactor, pcom(3) * tubi.ssfactor, 'o')
                        plot3(dpt(1) * tubi.ssfactor, dpt(2) * tubi.ssfactor, dpt(3) * tubi.ssfactor, 'o')
                        axis equal
                        if ii == 1
                            view(0, 90)
                        elseif ii == 2
                            view(90, 0)
                        else
                            view(180, 0)
                        end
                    end
                    legend({'surface', 'anterior pt', 'posterior pt', 'dorsal pt'}, ...
                'Location', 'northwest')
                    sgtitle('APD points for centerline extraction')
                    saveas(gcf, fullfile(tubi.dir.mesh, 'apd_pts_centerline.png'))
                end

            end
            % Save raw data to .mat
            save(rawapdvmatname, 'apts', 'ppts')
            clearvars adat pdat
        end
        disp('done determining apts, ppts')
    elseif autoAP
        % No ilastik files used to extract probabilities, instead use mesh
        % elongation axis at t0 and then pointmatch for t>t0 and t<t0.
        
        % First do t0
        ssfactor = tubi.ssfactor ;
        tubi.setTime(tubi.t0set()) ;
        meshfn = replace(tubi.fullFileBase.mesh, tubi.timeStampStringSpec, ...
            num2str(tubi.t0set(), tubi.timeStampStringSpec)) ;
        disp(['Loading mesh ' meshfn])
        mesh = read_ply_mod(meshfn );
        cntrd = mean(mesh.v) ;
        moi = momentOfInertia3D(mesh.v) ; 
        % Ascertain the long axis of the surface at this timepoint
        [eigvect, eigvals] = eig(moi) ;
        [~, ind] = min(abs([eigvals(1,1), eigvals(2,2), eigvals(3,3)])) ;
        % which data axis does this correspond to most closely?
        dotprods = [dot(eigvect(:, ind), [1, 0, 0]), ...
            dot(eigvect(:, ind), [0, 1, 0]), ...
            dot(eigvect(:, ind), [0, 0, 1]) ] ;
        [~, xIndex] = max(abs(dotprods)) ;
        axx = circshift([1,2,3],-xIndex+1) ;
        assert(xIndex == axx(1))
        
        % Place anterior at the intersection of x=xmin and the ray
        % emanating from the centroid along eigenvector
        % Check that the moment of inertia eigvect is not in plane
        % and that they are not parallel. Otherwise use Descartes formula:
        % ax + by + cz + d = 0, where n = [a, b, c] is a vector normal to the plane
        
        if ~swapAP
            % anterior point -- near along the elongated axis
            xval = min(mesh.v(:, xIndex)) ;
            % Store this near/far info 
            ptInPlaneA = [0,0,0] ;
            ptInPlaneA(xIndex) = xval ;
            
            % posterior point -- far along the elongated axis
            xval = max(mesh.v(:, xIndex)) ;
            ptInPlaneP = [0,0,0] ;
            ptInPlaneP(xIndex) = xval ;
        else
            % anterior point -- near along the elongated axis
            xval = max(mesh.v(:, xIndex)) ;
            ptInPlaneA = [0,0,0] ;
            ptInPlaneA(xIndex) = xval ;
            
            % posterior point -- far along the elongated axis
            xval = min(mesh.v(:, xIndex)) ;
            ptInPlaneP = [0,0,0] ;
            ptInPlaneP(xIndex) = xval ;
            
        end
        
        
        normalToPlane = [0,0,0] ;
        normalToPlane(xIndex) = 1 ; 
        lineDirec = eigvect(:, ind) ;
        [apt, specialCaseA] = linePlaneIntersection(lineDirec, cntrd, ...
            normalToPlane, ptInPlaneA) ;
        [ppt, specialCaseP] = linePlaneIntersection(lineDirec, cntrd, ...
            normalToPlane, ptInPlaneP) ;
        try
            assert(~specialCaseA && ~specialCaseP)
        catch
            disp('Failed to compute automatic endcap points. Is the surface flat?')
        end
        
        % Assignment for t0
        t0 = tubi.t0set() ;
        tidx0 = tubi.xp.tIdx(t0) ;
        apts(tidx0, :) = apt / ssfactor ;
        ppts(tidx0, :) = ppt / ssfactor ;
                
        tidxGreater = find(timePoints > t0) ;
        tidxSmaller = find(timePoints < t0) ;
        prevA = apts(tidx0, :) * ssfactor ;
        prevP = ppts(tidx0, :) * ssfactor ;
        for tidx = tidxGreater
            disp(['finding matching points in future timepoints > t0: t=' num2str(timePoints(tidx))])
            tubi.setTime(timePoints(tidx)) ;
            mesh = tubi.loadCurrentRawMesh() ;
            [~,idxA] = min(...
                (mesh.v(:,1) - prevA(1)).^2 + ...
                (mesh.v(:,2) - prevA(2)).^2 + ...
                (mesh.v(:,3) - prevA(3)).^2);
            [~,idxP] = min(...
                (mesh.v(:,1) - prevP(1)).^2 + ...
                (mesh.v(:,2) - prevP(2)).^2 + ...
                (mesh.v(:,3) - prevP(3)).^2);
            apt = mesh.v(idxA, :) ;
            ppt = mesh.v(idxP, :) ;
            
            % Check that this is working
            clf
            trisurf(triangulation(mesh.f, mesh.v), 'edgecolor', 'none') ;
            hold on;
            plot3(prevA(1), prevA(2), prevA(3), 'bo')
            plot3(prevP(1), prevP(2), prevP(3), 'ro')
            plot3(apts(:, 1), apts(:, 2), apts(:,3), '.-')
            plot3(ppts(:, 1), ppts(:, 2), ppts(:,3), '.-')
            
            apts(tidx, :) = apt / ssfactor ;
            ppts(tidx, :) = ppt / ssfactor ;
            prevA = apt ; 
            prevP = ppt ;
        end
        
        % Now point match backward in time
        prevA = apts(tidx0, :) * ssfactor ;
        prevP = ppts(tidx0, :) * ssfactor ;
        for tidx = fliplr(tidxSmaller)
            tubi.setTime(timePoints(tidx)) ;
            mesh = tubi.loadCurrentRawMesh() ;
            [~,idxA] = min(...
                (mesh.v(:,1) - prevA(1)).^2 + ...
                (mesh.v(:,2) - prevA(2)).^2 + ...
                (mesh.v(:,3) - prevA(3)).^2);
            [~,idxP] = min(...
                (mesh.v(:,1) - prevP(1)).^2 + ...
                (mesh.v(:,2) - prevP(2)).^2 + ...
                (mesh.v(:,3) - prevP(3)).^2);
            apt = mesh.v(idxA, :) ;
            ppt = mesh.v(idxP, :) ;
            apts(tidx, :) = apt / ssfactor ;
            ppts(tidx, :) = ppt / ssfactor ;
            prevA = apt ; 
            prevP = ppt ;
        end
    else
        % No ilastik files used to extract probabilities, instead just
        % click on points in 3D on mesh and use point matching to propagate
        % forward and backward in time from t0.
        msg = ['No ilastik files used to extract probabilities, instead just',...
            'click on points in 3D on mesh and use point matching to propagate',...
            'forward and backward in time from t0.'] ;
        disp(msg)
        % First do t0
        ssfactor = tubi.ssfactor ;
        tubi.setTime(tubi.t0set()) ;
        meshfn = replace(tubi.fullFileBase.mesh, tubi.timeStampStringSpec, ...
            sprintf(tubi.timeStampStringSpec, tubi.t0set())) ;
        disp(['Loading mesh ' meshfn])
        mesh = read_ply_mod( meshfn );
        
        %% getpts3d Select points from a 3D scatter plot by clicking on plot
        close all
        h = figure(1);
        clf
        vrs = tubi.xyz2APDV(mesh.v) ;
        trisurf(triangulation(mesh.f, vrs), 'edgecolor', 'none', 'facealpha',0.5)
        axis equal
        xlabel('x'); ylabel('y'); zlabel('z')
        
        % View ANTERIOR endcap 
        msg = 'Rotate the mesh to view Anterior endcap, then press Continue button (in bottom left of Figure)';
        disp(msg)
        title(msg)
        % key = 'none' ;
        % while ~strcmpi(key, 'return')
        %     waitforbuttonpress;
        %     key=get(gcf,'CurrentKey');
        % end
        
        c = uicontrol('String', 'Continue', 'Callback', 'uiresume(gcf)') ;
        uiwait(gcf)
        datacursormode on
        
        % View ANTERIOR endcap 
        msg = "Select Anterior endcap point, then press Continue button (in bottom left of Figure)";
        disp(msg)
        title(msg)
        c = uicontrol('String', 'Continue', 'Callback', 'uiresume(gcf)') ;
        uiwait(gcf)
                
        %msg = "Select Anterior endcap point, then press 'a' (with Fig in foreground)";
        % key = 'none' ;
        % while ~strcmpi(key, 'a')
        %     datacursormode on
        %     waitforbuttonpress;
        %     key=get(gcf,'CurrentKey');
        % end
        dcm_obj = datacursormode(h);  
        f = getCursorInfo(dcm_obj);
        aclick = f.Position ;
        apt = tubi.APDV2xyz(aclick) ;
        hold on;
        plot3(aclick(1), aclick(2), aclick(3), 'ro') ;
        legend({'surface', 'anterior'})
        
        %%%%%%%%  
        % Rotate to see posterior
        [az, el] = view ;
        view([az+180,el])
        
        % View POSTERIOR endcap         
        msg = 'Rotate the mesh to view Posterior endcap, then press Continue button (in bottom left of Figure)';
        disp(msg)
        title(msg)
        c = uicontrol('String', 'Continue', 'Callback', 'uiresume(gcf)') ;
        uiwait(gcf)
                
        
        % msg = 'Rotate the mesh to view Posterior endcap, then press Enter/return';
        % disp(msg)
        % title(msg)
        % key = 'none' ;
        % while ~strcmpi(key, 'return')
        %     waitforbuttonpress;
        %     key=get(gcf,'CurrentKey');
        % end
        datacursormode on
        % msg = "Select the Posterior endcap point, then press 'p' (with Fig in foreground)";
        % disp(msg)
        % title(msg)
        % key = 'none' ;
        % while ~strcmpi(key, 'p')
        %     datacursormode on
        %     waitforbuttonpress;
        %     key=get(gcf,'CurrentKey');
        % end   
        msg = "Select the Posterior endcap point, then press Continue button (in bottom left of Figure)";
        disp(msg)
        title(msg)
        c = uicontrol('String', 'Continue', 'Callback', 'uiresume(gcf)') ;
        uiwait(gcf)
        
        dcm_obj = datacursormode(h);
        f = getCursorInfo(dcm_obj);
        pclick = f.Position ;
        ppt = tubi.APDV2xyz(pclick) ;
        hold on;
        plot3(pclick(1), pclick(2), pclick(3), 'rs') ;
        legend({'surface', 'anterior', 'posterior'})
        disp('Anterior and Posterior endcap points have been successfully selected, closing figure in 3 seconds...')
        pause(3) ;
        close all
        
        % Assignment for t0
        t0 = tubi.t0set() ;
        tidx0 = tubi.xp.tIdx(t0) ;
        apts(tidx0, :) = apt / ssfactor ;
        ppts(tidx0, :) = ppt / ssfactor ;
                
        tidxGreater = find(timePoints > t0) ;
        tidxSmaller = find(timePoints < t0) ;
        prevA = apts(tidx0, :) * ssfactor ;
        prevP = ppts(tidx0, :) * ssfactor ;
        for tidx = tidxGreater
            tubi.setTime(t0) ;
            mesh = tubi.loadCurrentRawMesh() ;
            [~,idxA] = min(...
                (mesh.v(:,1) - prevA(1)).^2 + ...
                (mesh.v(:,2) - prevA(2)).^2 + ...
                (mesh.v(:,3) - prevA(3)).^2);
            [~,idxP] = min(...
                (mesh.v(:,1) - prevP(1)).^2 + ...
                (mesh.v(:,2) - prevP(2)).^2 + ...
                (mesh.v(:,3) - prevP(3)).^2);
            apt = mesh.v(idxA, :) ;
            ppt = mesh.v(idxP, :) ;
            
            % Check that this is working
            clf
            trisurf(triangulation(mesh.f, mesh.v), 'edgecolor', 'none') ;
            hold on;
            plot3(prevA(1), prevA(2), prevA(3), 'ro')
            plot3(prevP(1), prevP(2), prevP(3), 'bs')
            plot3(apts(:, 1)*ssfactor, apts(:, 2)*ssfactor, apts(:,3)*ssfactor, '.-')
            plot3(ppts(:, 1)*ssfactor, ppts(:, 2)*ssfactor, ppts(:,3)*ssfactor, '.-')
            
            apts(tidx, :) = apt / ssfactor ;
            ppts(tidx, :) = ppt / ssfactor ;
            prevA = apt ; 
            prevP = ppt ;
        end
        
        % Now point match backward in time
        prevA = apts(tidx0, :) * ssfactor ;
        prevP = ppts(tidx0, :) * ssfactor ;
        for tidx = fliplr(tidxSmaller)
            tubi.setTime(timePoints(tidx)) ;
            mesh = tubi.loadCurrentRawMesh() ;
            [~,idxA] = min(...
                (mesh.v(:,1) - prevA(1)).^2 + ...
                (mesh.v(:,2) - prevA(2)).^2 + ...
                (mesh.v(:,3) - prevA(3)).^2);
            [~,idxP] = min(...
                (mesh.v(:,1) - prevP(1)).^2 + ...
                (mesh.v(:,2) - prevP(2)).^2 + ...
                (mesh.v(:,3) - prevP(3)).^2);
            apt = mesh.v(idxA, :) ;
            ppt = mesh.v(idxP, :) ;
            apts(tidx, :) = apt / ssfactor ;
            ppts(tidx, :) = ppt / ssfactor ;
            prevA = apt ; 
            prevP = ppt ;
        end
                
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Smooth the apt and ppt data
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if length(timePoints) > 2 
        if smwindow > 0
            disp('Smoothing apts and ppts...')
            apts_sm = 0 * apts ;
            ppts_sm = 0 * apts ;
            % fraction of data for smoothing window
            smfrac = smwindow / double(length(timePoints)) ;  
            if smfrac > 1 
                smfrac = 1 ;
            end
            apts_sm(:, 1) = smooth(timePoints, apts(:, 1), smfrac, 'rloess');
            ppts_sm(:, 1) = smooth(timePoints, ppts(:, 1), smfrac, 'rloess');
            apts_sm(:, 2) = smooth(timePoints, apts(:, 2), smfrac, 'rloess');
            ppts_sm(:, 2) = smooth(timePoints, ppts(:, 2), smfrac, 'rloess');
            apts_sm(:, 3) = smooth(timePoints, apts(:, 3), smfrac, 'rloess');
            ppts_sm(:, 3) = smooth(timePoints, ppts(:, 3), smfrac, 'rloess');
        else
            disp('No smoothing to acom and ppts...')
            apts_sm = apts ;
            ppts_sm = ppts ;
        end
    else
        apts_sm = apts ;
        ppts_sm = ppts ;
    end
    
    if preview
        plot(timePoints, apts - mean(apts,1), '.')
        hold on
        plot(timePoints, apts_sm - mean(apts, 1), '-')
        sgtitle('Smoothed COMs for AP')
    end
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Save smoothed anterior and posterior centers of mass ===============
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    try
        h5create(rawapdvname, '/apts', size(apts)) ;
    catch
        disp(['apts already exists in h5 file. Overwriting: ' rawapdvname])
    end
    try
        h5create(rawapdvname, '/ppts', size(ppts)) ;
    catch
        disp(['ppts already exists in h5 file. Overwriting: ' rawapdvname])
    end
    try
        h5create(rawapdvname, '/apts_sm', size(apts_sm)) ;
    catch
        disp(['apts_sm already exists in h5 file. Overwriting: ' rawapdvname])
    end
    try
        h5create(rawapdvname, '/ppts_sm', size(ppts_sm)) ;
    catch
        disp(['ppts_sm already exists in h5 file. Overwriting: ' rawapdvname])
    end
    h5write(rawapdvname, '/apts', apts) ;
    h5write(rawapdvname, '/ppts', ppts) ;
    h5write(rawapdvname, '/apts_sm', apts_sm) ;
    h5write(rawapdvname, '/ppts_sm', ppts_sm) ;
else
    disp('Skipping, since already loaded apts_sm and ppts_sm')
    if preview
        apts_sm = h5read(rawapdvname, '/apts_sm');
        ppts_sm = h5read(rawapdvname, '/ppts_sm');
        plot3(apts_sm(:, 1), apts_sm(:, 2), apts_sm(:, 3))
        hold on;
        plot3(ppts_sm(:, 1), ppts_sm(:, 2), ppts_sm(:, 3))
        xlabel('x [subsampled pix]')
        ylabel('y [subsampled pix]')
        zlabel('z [subsampled pix]')
        axis equal
        pause(1)
    end
end

disp('done with AP COMs')

%% Display APDV COMS over time
try
    dpt = dlmread(tubi.fileName.dpt) ;
    % [xyzlim, ~, ~, ~] = tubi.getXYZLims() ;
    for tidx = 1:length(timePoints)
        tp = timePoints(tidx) ;
        tubi.setTime(tp) ;
        mesh = tubi.getCurrentRawMesh() ;
        mesh.v = mesh.v / tubi.ssfactor ; % tubi.xyz2APDV(mesh.v) ;
        % Plot the APDV points
        clf
        trisurf(triangulation(mesh.f, mesh.v), 'edgecolor', 'none', 'facealpha', 0.2)
        hold on;
        plot3(apts_sm(tidx, 1), apts_sm(tidx, 2), apts_sm(tidx, 3), 'ro')
        plot3(apts(tidx, 1), apts(tidx, 2), apts(tidx, 3), 'r.')
        plot3(ppts_sm(tidx, 1), ppts_sm(tidx, 2), ppts_sm(tidx, 3), 'b^')
        plot3(ppts(tidx, 1), ppts(tidx, 2), ppts(tidx, 3), 'b.')
        plot3(dpt(1, 1), dpt(1, 2), dpt(1, 3), 'cs')
        axis equal
        legend({'surface', 'A', 'A smoothed', 'P', 'P smoothed', 'D'}) 
        title(['t = ', num2str(tp)]) 
        pause(0.1)
    end
catch
    disp('Could not display aligned meshes -- does dpt exist on file?')
end

disp('done')