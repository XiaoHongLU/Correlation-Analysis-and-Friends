function [dev, test, bestDevAccuracy, U, bestNeighbor,bestregX, bestregY ] = cca()
clear all;
close all;

%% Load data and list the data variables 
path=sprintf('../DATA/MAT/%s[numfr1=7,numfr2=7]',spkr);
load(path, 'MFCC', 'X', 'P');
X1 = MFCC;        %273 x 50948 view1
X2 = X;           %112 x 50948 view2
n = size(X1, 2);

%randomly permute data:
perm = randperm(n);
X1 = X1(:, perm);
X2 = X2(:, perm);
P = P(:, perm);

%Speaker and number of frames stacked
spkr='JW11'; %number of frames stacked = 7
train = 35000; %25948;
dev   = 45000; %40948;
test  = 50000; %50948;

%data to be used
X1train = X1(:, 1:train);
X1dev = X1(:, train+1:dev);
X1test = X1(:, dev+1:test);
X2train = X2(:, 1:train);
ytrain = P(:, 1:train);
ydev = P(:, train+1:dev);
ytest = P(:, dev+1:test); 
baselineAcousticTrain = X1train(118:156, :)';
baselineAcousticDev = X1dev(118:156, :)';
baselineAcousticTest = X1test(118:156, :)';
display('loaded data');

%%center data
X1train = centerAndNormalize(X1train);
X2train = centerAndNormalize(X2train);
X1dev = centerAndNormalize(X1dev);
X1test = centerAndNormalize(X1test);

% mean = sum(X1train, 2)/size(X1train, 2);
% X1train = bsxfun(@minus, X1train, mean);
% mean = sum(X2train, 2)/size(X2train, 2);
% X2train = bsxfun(@minus, X2train, mean);
% mean = sum(X1dev, 2)/size(X1dev, 2);
% X1dev = bsxfun(@minus, X1dev, mean);
% mean = sum(X1test, 2)/size(X1test, 2);
% X1test = bsxfun(@minus, X1test, mean);

%hyperparameters
D = [30, 50, 70, 90, 110];
regulars = [1E-6, 1E-4, 1E-2, 1E-1, 10];
neighbors = [4, 8, 12, 16];
counter = 0;
numSteps = length(D)*length(neighbors)*length(regulars);

%outputs
dev = [];
test = [];
bestDevAccuracy = 0;
bestU = [];
bestNeighbor = 0;
bestregX = 0;
bestregY = 0;
bestd = 0;



a = figure;
b = figure;
h = waitbar(0,'Please wait...');
for i=length(regulars):-1:1
    for j=length(regulars):-1:1
        
        [U,~,~] = calc_cca(X1train,X2train, regulars(i), regulars(j));
        
        for k = 1:length(D)
            %take top d feature vectors
%             [U,~,~] = calc_cca(X1train,X2train, regulars(i), regulars(j));
            top_d = U(:, 1:D(k)); %273 by d matrix
            
            %project train, dev, test data onto top_d correlated components
            learnedFeaturesTrain = top_d'*X1train; %d by n, n = 8527
            learnedFeaturesDev = top_d'*X1dev;

            %now stack the 39 x n baseline acoustic feature vector onto proj
            stackedTrain = [baselineAcousticTrain'; learnedFeaturesTrain]; %matrix (39 + d) by n
            stackedDev = [baselineAcousticDev'; learnedFeaturesDev];
            
            %train and classify the KNN
            for n = 1:length(neighbors)
                mdl = fitcknn(stackedTrain', ytrain, 'NumNeighbors', neighbors(n));
                
                %predict labels for dev data
                [labeldev, ~] = predict(mdl,stackedDev');
                
                %compute and store accuracy
                dev = [dev sum(ydev' == labeldev)/length(ydev)];
                
                %record best parameters and feature vectors
                if (dev(end) > bestDevAccuracy)
                    bestDevAccuracy = dev(end);
                    bestU = U; %recall top_d = U(:, 1:D(k))
                    bestNeighbor = n;
                    bestregX = regulars(i);
                    bestregY = regulars(j);
                    bestd = D(k);
                    %plot only when it looks good
                    fprintf('d: %f , regX: %d, regY: %d, numNeighbors: %d, devAcc: %f\n', ...
                        D(i), regulars(j), regulars(j), neighbors(n), dev(end));
                    figure(a)
                    gscatter((U(:, 1)'*X1train)', (U(:, 2)'*X1train)', ytrain);
                    drawnow
                    figure(b)
                    gscatter(U(:, 1)'*X1test, U(:, 2)'*X1test, ytest);
                    drawnow
                    
                end
                waitbar(counter / numSteps);
                counter = counter +1;
            end
        end
    end
end
close(h);

%now try on the test data:
top_d = bestU(:, 1:bestd); %273 by d matrix
learnedFeaturesTrain = top_d'*X1train; %d by n, n = 8527
learnedFeaturesTest = top_d'*X1test;
stackedTrain = [baselineAcousticTrain'; learnedFeaturesTrain];
stackedTest = [baselineAcousticTest'; learnedFeaturesTest];

mdl = fitcknn(stackedTrain', ytrain, 'NumNeighbors', bestNeighbor);
[labeltest, ~] = predict(mdl,stackedTest');
display('test accuracy');
test = sum(ytest' == labeltest)/length(ytest)
c = figure;
fprintf('bestDevAccuracy: %f, bestNeighbor: %d, bestRegX: %d, bestRegY: %d, bestDim: %d, testAccuracy, %f', ...
    bestDevAccuracy, bestNeighbor, bestregX, bestregY, bestd, test);
gscatter(bestU(:, 1)'*X1test, bestU(:, 2)'*X1test, ytest);

save('CCAprojected_data', stackedTrain, stackedTest, ytrain, ytest, bestd, bestRegX, bestRegY);

end
       

function [] = plot2d(a, C, labels)
    figure(a);
    scatter(C(:, 1), C(:, 2), 9, labels)
end


function X = centerAndNormalize(X)
    mean = sum(X, 2)/size(X, 2);
    stdtrain = std(X');
    Xcenter = bsxfun(@minus, X, mean);
    X = bsxfun(@rdivide, Xcenter, stdtrain');
end

function [U, V, r] = calc_cca(X,Y, regX, regY)

% CCA calculate canonical correlations
%
% [Wx Wy r] = cca(X,Y) where Wx and Wy contains the canonical correlation
% vectors as columns and r is a vector with corresponding canonical
% correlations. The correlations are sorted in descending order. X and Y
% are matrices where each column is a sample. Hence, X and Y must have
% the same number of columns.
%
% Example: If X is M*K and Y is N*K there are L=MIN(M,N) solutions. Wx is
% then M*L, Wy is N*L and r is L*1.
%
%
% © 2000 Magnus Borga, Linköpings universitet

% --- Calculate covariance matrices ---
z = [X;Y];
C = cov(z.');
sx = size(X,1);
sy = size(Y,1);
%added by Corby: regularization terms
Cxx = C(1:sx, 1:sx) + regX*eye(sx);
Cxy = C(1:sx, sx+1:sx+sy);
Cyx = Cxy';
%added by Corby: regularization terms
Cyy = C(sx+1:sx+sy, sx+1:sx+sy) + regY*eye(sy);
invCyy = inv(Cyy);

% --- Calcualte Wx and r ---

[U,r] = eig(inv(Cxx)*Cxy*invCyy*Cyx); % Basis in X, U is left side
r = sqrt(real(r));      % Canonical correlations

% --- Sort correlations ---

% V = fliplr(U);		% reverse order of eigenvectors
% r = flipud(diag(r));	% extract eigenvalues anr reverse their orrer
% [r,I]= sort((real(r)));	% sort reversed eigenvalues in ascending order
% r = flipud(r);		% restore sorted eigenvalues into descending order
% for j = 1:length(I)
%   U(:,j) = V(:,I(j));  % sort reversed eigenvectors in ascending order
% end
% U = fliplr(U);	% restore sorted eigenvectors into descending order

% --- Calcualte Wy  ---

V = invCyy*Cyx*U;     % Basis in Y
V = V./repmat(sqrt(sum(abs(V).^2)),sy,1); % Normalize Wy
end
