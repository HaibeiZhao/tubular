function exportOBJ(mesh, filename)
% EXPORTOBJ  Export a mesh struct to a Wavefront OBJ file.
%
%   mesh: struct with fields:
%       v  -> Nx3 array of vertex coords
%       vn -> Nx3 array of vertex normals
%       u  -> Nx2 array of UV coords
%       f  -> Mx3 array of face indices (1-based)
%
%   filename: name of the .obj file to write

    fid = fopen(filename, 'w');
    if fid == -1
        error('Cannot open file: %s', filename);
    end
    
    fprintf('Writing OBJ file to %s...\n', filename);
    
    % Normalize UV coordinates (u)
    if isfield(mesh, 'u') && ~isempty(mesh.u)
        % Normalize each column (x and y) of the UV coordinates
        mesh.u(:,1) = mesh.u(:,1) / max(mesh.u(:,1));  % Normalize the x (u) values
        mesh.u(:,2) = mesh.u(:,2) / max(mesh.u(:,2));  % Normalize the y (v) values
    end
    
    % Write vertices (v)
    for i = 1:size(mesh.v,1)
        fprintf(fid, 'v %f %f %f\n', mesh.v(i,1), mesh.v(i,2), mesh.v(i,3));
    end

    % Write texture coordinates (vt)
    if isfield(mesh, 'u') && ~isempty(mesh.u)
        for i = 1:size(mesh.u,1)
            fprintf(fid, 'vt %f %f\n', mesh.u(i,1), mesh.u(i,2));
        end
    end
    
    % Write normals (vn)
    if isfield(mesh, 'vn') && ~isempty(mesh.vn)
        for i = 1:size(mesh.vn,1)
            fprintf(fid, 'vn %f %f %f\n', mesh.vn(i,1), mesh.vn(i,2), mesh.vn(i,3));
        end
    end
    
    % Write faces (f)
    %
    % The format below assumes that each face is a triangle and that vertex (v), 
    % texture (vt), and normal (vn) share the same 1-based index for the i-th vertex.
    % 'f v1/vt1/vn1 v2/vt2/vn2 v3/vt3/vn3'
    %
    % If your indexing for normals or texture coordinates differs, you need to adjust accordingly.
    
    for i = 1:size(mesh.f,1)
        v1 = mesh.f(i,1);
        v2 = mesh.f(i,2);
        v3 = mesh.f(i,3);
        
        % Build the face string according to the data available
        if ~isempty(mesh.u) && ~isempty(mesh.vn)
            % v/vt/vn for each vertex
            fprintf(fid, 'f %d/%d/%d %d/%d/%d %d/%d/%d\n', ...
                    v1, v1, v1, v2, v2, v2, v3, v3, v3);
        elseif ~isempty(mesh.u)
            % v/vt
            fprintf(fid, 'f %d/%d %d/%d %d/%d\n', ...
                    v1, v1, v2, v2, v3, v3);
        elseif ~isempty(mesh.vn)
            % v//vn
            fprintf(fid, 'f %d//%d %d//%d %d//%d\n', ...
                    v1, v1, v2, v2, v3, v3);
        else
            % just v
            fprintf(fid, 'f %d %d %d\n', v1, v2, v3);
        end
    end
    
    fclose(fid);
    fprintf('Done.\n');
end
