% %% ================================================================
% % CORRECTED GRADIENT-BASED MLP MODELS
% % 3 Inputs -> 24 Hidden Neurons -> 1 Output
% %
% % Optimizers:
% % BGD, SGD, MBGD, Momentum, NAG,
% % Adagrad, RMSProp, Adadelta, Adamax
% %
% % Dataset:
% % process_data(2).xlsx
% %
% % Inputs:
% %   x2 = Substrate concentration
% %   x4 = Biomass concentration
% %   x5 = Solvent concentration
% %
% % Outputs:
% %   y_fermentation
% %   y_interaction
% %   y_top_phase
% %   y_bottom_phase
% %
% % IMPORTANT:
% % - Chronological/trajectory-aware split
% % - Training-only normalization
% % - Validation used for early stopping
% % - Test set completely untouched until final evaluation
% % - Same 3-24-1 nonlinear architecture for all optimizers
% % - Multiple independent runs
% %% ================================================================
% 
% clear;
% clc;
% close all;
% 
% %% ================================================================
% % 1. USER SETTINGS
% %% ================================================================
% 
% filename = 'process_data.xlsx';
% 
% input_names = { ...
%     'Substrate Concentration', ...
%     'Biomass Concentration', ...
%     'Solvent Concentration'};
% 
% output_names = { ...
%     'Fermentation Product Concentration', ...
%     'Solvent-Product Complex Concentration', ...
%     'Top Phase Product Concentration', ...
%     'Bottom Phase Product Concentration'};
% 
% % Network architecture
% n_input  = 3;
% n_hidden = 24;
% n_output = 1;
% 
% % Hidden activation
% activation = 'tanh';
% 
% % Data split
% train_fraction = 0.70;
% val_fraction   = 0.15;
% test_fraction  = 0.15;
% 
% % Training settings
% max_epochs = 3000;
% patience   = 200;
% 
% % Mini-batch size
% mini_batch_size = 32;
% 
% % Independent runs
% n_runs = 10;
% 
% % Learning rate
% learning_rate = 0.001;
% 
% % L2 regularization
% lambda = 0;
% 
% % Gradient clipping
% gradient_clip = 5;
% 
% % Display
% verbose = true;
% 
% fprintf('\n============================================================\n');
% fprintf('CORRECTED GRADIENT-BASED MLP MODELING\n');
% fprintf('============================================================\n');
% 
% %% ================================================================
% % 2. LOAD DATA
% %% ================================================================
% 
% data = readtable(filename);
% 
% required_variables = { ...
%     'x2','x4','x5', ...
%     'y_fermentation', ...
%     'y_interaction', ...
%     'y_top_phase', ...
%     'y_bottom_phase', ...
%     'tspan'};
% 
% for i = 1:length(required_variables)
%     if ~ismember(required_variables{i}, data.Properties.VariableNames)
%         error('Required variable "%s" not found in dataset.', ...
%             required_variables{i});
%     end
% end
% 
% % Sort chronologically
% data = sortrows(data,'tspan');
% 
% X_raw = table2array(data(:,{'x2','x4','x5'}));
% 
% Y_raw = table2array(data(:,{ ...
%     'y_fermentation', ...
%     'y_interaction', ...
%     'y_top_phase', ...
%     'y_bottom_phase'}));
% 
% time = table2array(data(:,'tspan'));
% 
% [n_samples, n_inputs_actual] = size(X_raw);
% [~, n_outputs_actual] = size(Y_raw);
% 
% fprintf('\nNumber of observations = %d\n',n_samples);
% fprintf('Number of inputs       = %d\n',n_inputs_actual);
% fprintf('Number of outputs      = %d\n',n_outputs_actual);
% fprintf('Time range             = %.4f to %.4f h\n', ...
%     min(time),max(time));
% 
% if n_inputs_actual ~= 3
%     error('Expected exactly 3 input variables.');
% end
% 
% if n_outputs_actual ~= 4
%     error('Expected exactly 4 output variables.');
% end
% 
% %% ================================================================
% % 3. CHECK FOR MISSING / NONFINITE DATA
% %% ================================================================
% 
% if any(~isfinite(X_raw(:)))
%     error('Non-finite values detected in input data.');
% end
% 
% if any(~isfinite(Y_raw(:)))
%     error('Non-finite values detected in output data.');
% end
% 
% %% ================================================================
% % 4. TRAJECTORY-AWARE CHRONOLOGICAL SPLIT
% %
% % Because the current dataset contains time-resolved observations,
% % neighboring observations should not be randomly distributed
% % between training and testing.
% %
% % 70% earliest observations  -> TRAIN
% % 15% next observations      -> VALIDATION
% % 15% latest observations    -> TEST
% %
% % NOTE:
% % This evaluates temporal extrapolation/generalization.
% % It is NOT equivalent to testing independent operating conditions.
% %% ================================================================
% 
% n_train = floor(train_fraction*n_samples);
% n_val   = floor(val_fraction*n_samples);
% n_test  = n_samples - n_train - n_val;
% 
% train_idx = 1:n_train;
% 
% val_idx = ...
%     (n_train+1):(n_train+n_val);
% 
% test_idx = ...
%     (n_train+n_val+1):n_samples;
% 
% X_train_raw = X_raw(train_idx,:);
% Y_train_raw = Y_raw(train_idx,:);
% 
% X_val_raw = X_raw(val_idx,:);
% Y_val_raw = Y_raw(val_idx,:);
% 
% X_test_raw = X_raw(test_idx,:);
% Y_test_raw = Y_raw(test_idx,:);
% 
% time_train = time(train_idx);
% time_val   = time(val_idx);
% time_test  = time(test_idx);
% 
% fprintf('\n------------------------------------------------------------\n');
% fprintf('TRAJECTORY-AWARE DATA SPLIT\n');
% fprintf('------------------------------------------------------------\n');
% 
% fprintf('Training   : %d samples | %.4f - %.4f h\n', ...
%     length(train_idx),min(time_train),max(time_train));
% 
% fprintf('Validation : %d samples | %.4f - %.4f h\n', ...
%     length(val_idx),min(time_val),max(time_val));
% 
% fprintf('Testing    : %d samples | %.4f - %.4f h\n', ...
%     length(test_idx),min(time_test),max(time_test));
% 
% %% ================================================================
% % 5. TRAINING-ONLY MIN-MAX NORMALIZATION
% %
% % IMPORTANT:
% % min/max are calculated ONLY from training data.
% %
% % Validation and test data are transformed using the same
% % training-derived parameters.
% %% ================================================================
% 
% X_min = min(X_train_raw,[],1);
% X_max = max(X_train_raw,[],1);
% 
% Y_min = min(Y_train_raw,[],1);
% Y_max = max(Y_train_raw,[],1);
% 
% % Prevent division by zero
% X_range = X_max - X_min;
% Y_range = Y_max - Y_min;
% 
% X_range(X_range == 0) = 1;
% Y_range(Y_range == 0) = 1;
% 
% % Normalize
% X_train = (X_train_raw - X_min) ./ X_range;
% X_val   = (X_val_raw   - X_min) ./ X_range;
% X_test  = (X_test_raw  - X_min) ./ X_range;
% 
% Y_train = (Y_train_raw - Y_min) ./ Y_range;
% Y_val   = (Y_val_raw   - Y_min) ./ Y_range;
% Y_test  = (Y_test_raw  - Y_min) ./ Y_range;
% 
% fprintf('\nTraining-only min-max normalization applied.\n');
% 
% %% ================================================================
% % 6. DEFINE OPTIMIZERS
% %% ================================================================
% 
% optimizer_names = { ...
%     'BGD', ...
%     'SGD', ...
%     'MBGD', ...
%     'Momentum', ...
%     'NAG', ...
%     'Adagrad', ...
%     'RMSProp', ...
%     'Adadelta', ...
%     'Adamax'};
% 
% n_optimizers = length(optimizer_names);
% 
% %% ================================================================
% % 7. STORAGE
% %% ================================================================
% 
% results = struct();
% 
% for opt = 1:n_optimizers
% 
%     results(opt).name = optimizer_names{opt};
% 
%     results(opt).R2_train  = zeros(n_outputs_actual,n_runs);
%     results(opt).R2_val    = zeros(n_outputs_actual,n_runs);
%     results(opt).R2_test   = zeros(n_outputs_actual,n_runs);
% 
%     results(opt).RMSE_train = zeros(n_outputs_actual,n_runs);
%     results(opt).RMSE_val   = zeros(n_outputs_actual,n_runs);
%     results(opt).RMSE_test  = zeros(n_outputs_actual,n_runs);
% 
%     results(opt).MAE_train = zeros(n_outputs_actual,n_runs);
%     results(opt).MAE_val   = zeros(n_outputs_actual,n_runs);
%     results(opt).MAE_test  = zeros(n_outputs_actual,n_runs);
% 
%     results(opt).MSE_train = zeros(n_outputs_actual,n_runs);
%     results(opt).MSE_val   = zeros(n_outputs_actual,n_runs);
%     results(opt).MSE_test  = zeros(n_outputs_actual,n_runs);
% 
%     results(opt).best_epoch = zeros(n_outputs_actual,n_runs);
% 
% end
% 
% %% ================================================================
% % 8. MAIN TRAINING LOOP
% %
% % Each output is modeled separately:
% %
% %       3 inputs
% %          |
% %      24 tanh neurons
% %          |
% %      1 linear output
% %
% % Same architecture for all optimizers.
% %% ================================================================
% 
% for opt = 1:n_optimizers
% 
%     fprintf('\n============================================================\n');
%     fprintf('OPTIMIZER: %s\n',optimizer_names{opt});
%     fprintf('============================================================\n');
% 
%     for out = 1:n_outputs_actual
% 
%         fprintf('\nOutput %d/%d: %s\n', ...
%             out,n_outputs_actual,output_names{out});
% 
%         for run = 1:n_runs
% 
%             % ----------------------------------------------------
%             % Reproducible independent initialization
%             % ----------------------------------------------------
%             seed = 1000 + 100*opt + run;
%             rng(seed);
% 
%             y_train = Y_train(:,out);
%             y_val   = Y_val(:,out);
%             y_test  = Y_test(:,out);
% 
%             % ----------------------------------------------------
%             % Initialize network
%             % ----------------------------------------------------
%             net = initialize_network(n_input,n_hidden);
% 
%             % ----------------------------------------------------
%             % Initialize optimizer state
%             % ----------------------------------------------------
%             state = initialize_optimizer_state(net,optimizer_names{opt});
% 
%             best_net = net;
%             best_val_loss = inf;
%             best_epoch = 0;
%             wait = 0;
% 
%             % ----------------------------------------------------
%             % Training
%             % ----------------------------------------------------
%             for epoch = 1:max_epochs
% 
%                 % ================================================
%                 % Generate training batches
%                 % ================================================
% 
%                 if strcmp(optimizer_names{opt},'BGD')
% 
%                     batch_indices = {1:size(X_train,1)};
% 
%                 elseif strcmp(optimizer_names{opt},'SGD')
% 
%                     order = randperm(size(X_train,1));
% 
%                     batch_indices = cell(size(X_train,1),1);
% 
%                     for b = 1:size(X_train,1)
%                         batch_indices{b} = order(b);
%                     end
% 
%                 else
% 
%                     order = randperm(size(X_train,1));
% 
%                     n_batches = ceil(size(X_train,1)/mini_batch_size);
% 
%                     batch_indices = cell(n_batches,1);
% 
%                     for b = 1:n_batches
% 
%                         start_idx = (b-1)*mini_batch_size + 1;
%                         end_idx = min(b*mini_batch_size,size(X_train,1));
% 
%                         batch_indices{b} = ...
%                             order(start_idx:end_idx);
% 
%                     end
% 
%                 end
% 
%                 % ================================================
%                 % Training batches
%                 % ================================================
% 
%                 for b = 1:length(batch_indices)
% 
%                     idx_batch = batch_indices{b};
% 
%                     Xb = X_train(idx_batch,:);
%                     yb = y_train(idx_batch,:);
% 
%                     % --------------------------------------------
%                     % NAG look-ahead
%                     % --------------------------------------------
% 
%                     if strcmp(optimizer_names{opt},'NAG')
% 
%                         lookahead = net;
% 
%                         lookahead.W1 = ...
%                             net.W1 + 0.9*state.vW1;
% 
%                         lookahead.b1 = ...
%                             net.b1 + 0.9*state.vb1;
% 
%                         lookahead.W2 = ...
%                             net.W2 + 0.9*state.vW2;
% 
%                         lookahead.b2 = ...
%                             net.b2 + 0.9*state.vb2;
% 
%                         [~,grads] = network_gradient( ...
%                             lookahead,Xb,yb,lambda);
% 
%                     else
% 
%                         [~,grads] = network_gradient( ...
%                             net,Xb,yb,lambda);
% 
%                     end
% 
%                     % --------------------------------------------
%                     % Gradient clipping
%                     % --------------------------------------------
% 
%                     grads = clip_gradients(grads,gradient_clip);
% 
%                     % --------------------------------------------
%                     % Optimizer update
%                     % --------------------------------------------
% 
%                     [net,state] = optimizer_update( ...
%                         net,state,grads, ...
%                         optimizer_names{opt}, ...
%                         learning_rate,epoch);
% 
%                 end
% 
%                 % ================================================
%                 % Validation loss
%                 % ================================================
% 
%                 y_val_pred = network_predict(net,X_val);
% 
%                 val_loss = mean((y_val-y_val_pred).^2);
% 
%                 % ================================================
%                 % Early stopping
%                 % ================================================
% 
%                 if val_loss < best_val_loss
% 
%                     best_val_loss = val_loss;
% 
%                     best_net = net;
% 
%                     best_epoch = epoch;
% 
%                     wait = 0;
% 
%                 else
% 
%                     wait = wait + 1;
% 
%                 end
% 
%                 if wait >= patience
%                     break;
%                 end
% 
%             end
% 
%             % ----------------------------------------------------
%             % Restore best validation model
%             % ----------------------------------------------------
% 
%             net = best_net;
% 
%             % ----------------------------------------------------
%             % Final predictions
%             % ----------------------------------------------------
% 
%             pred_train = network_predict(net,X_train);
%             pred_val   = network_predict(net,X_val);
%             pred_test  = network_predict(net,X_test);
% 
%             % ----------------------------------------------------
%             % Metrics
%             % ----------------------------------------------------
% 
%             [R2tr,RMSEtr,MAEtr,MSEtr] = ...
%                 calculate_metrics(y_train,pred_train);
% 
%             [R2v,RMSEv,MAEv,MSEv] = ...
%                 calculate_metrics(y_val,pred_val);
% 
%             [R2te,RMSEte,MAEte,MSEte] = ...
%                 calculate_metrics(y_test,pred_test);
% 
%             results(opt).R2_train(out,run) = R2tr;
%             results(opt).R2_val(out,run)   = R2v;
%             results(opt).R2_test(out,run)  = R2te;
% 
%             results(opt).RMSE_train(out,run) = RMSEtr;
%             results(opt).RMSE_val(out,run)   = RMSEv;
%             results(opt).RMSE_test(out,run)  = RMSEte;
% 
%             results(opt).MAE_train(out,run) = MAEtr;
%             results(opt).MAE_val(out,run)   = MAEv;
%             results(opt).MAE_test(out,run)  = MAEte;
% 
%             results(opt).MSE_train(out,run) = MSEtr;
%             results(opt).MSE_val(out,run)   = MSEv;
%             results(opt).MSE_test(out,run)  = MSEte;
% 
%             results(opt).best_epoch(out,run) = best_epoch;
% 
%             % Store final run predictions
%             if run == 1
% 
%                 results(opt).pred_train{out} = pred_train;
%                 results(opt).pred_val{out}   = pred_val;
%                 results(opt).pred_test{out}  = pred_test;
% 
%                 results(opt).network{out} = net;
% 
%             end
% 
%             if verbose
% 
%                 fprintf(['Run %2d/%2d | Epoch %4d | ', ...
%                     'Train R2 = %.5f | Val R2 = %.5f | ', ...
%                     'Test R2 = %.5f\n'], ...
%                     run,n_runs,best_epoch,R2tr,R2v,R2te);
% 
%             end
% 
%         end
% 
%     end
% 
% end
% 
% %% ================================================================
% % 9. SUMMARY STATISTICS
% %% ================================================================
% 
% fprintf('\n\n============================================================\n');
% fprintf('FINAL TEST PERFORMANCE: MEAN ± SD\n');
% fprintf('============================================================\n');
% 
% summary_rows = {};
% 
% row = 1;
% 
% for opt = 1:n_optimizers
% 
%     for out = 1:n_outputs_actual
% 
%         R2_mean = mean(results(opt).R2_test(out,:));
%         R2_std  = std(results(opt).R2_test(out,:));
% 
%         RMSE_mean = mean(results(opt).RMSE_test(out,:));
%         RMSE_std  = std(results(opt).RMSE_test(out,:));
% 
%         MAE_mean = mean(results(opt).MAE_test(out,:));
%         MAE_std  = std(results(opt).MAE_test(out,:));
% 
%         MSE_mean = mean(results(opt).MSE_test(out,:));
%         MSE_std  = std(results(opt).MSE_test(out,:));
% 
%         fprintf('\n%s | %s\n', ...
%             optimizer_names{opt},output_names{out});
% 
%         fprintf('R2   = %.6f ± %.6f\n',R2_mean,R2_std);
%         fprintf('RMSE = %.6f ± %.6f\n',RMSE_mean,RMSE_std);
%         fprintf('MAE  = %.6f ± %.6f\n',MAE_mean,MAE_std);
%         fprintf('MSE  = %.8f ± %.8f\n',MSE_mean,MSE_std);
% 
%         summary_rows{row,1} = optimizer_names{opt};
%         summary_rows{row,2} = output_names{out};
%         summary_rows{row,3} = R2_mean;
%         summary_rows{row,4} = R2_std;
%         summary_rows{row,5} = RMSE_mean;
%         summary_rows{row,6} = RMSE_std;
%         summary_rows{row,7} = MAE_mean;
%         summary_rows{row,8} = MAE_std;
%         summary_rows{row,9} = MSE_mean;
%         summary_rows{row,10}= MSE_std;
% 
%         row = row + 1;
% 
%     end
% 
% end
% 
% summary_table = cell2table(summary_rows,...
%     'VariableNames',{ ...
%     'Optimizer',...
%     'Output',...
%     'R2_Mean',...
%     'R2_SD',...
%     'RMSE_Mean',...
%     'RMSE_SD',...
%     'MAE_Mean',...
%     'MAE_SD',...
%     'MSE_Mean',...
%     'MSE_SD'});
% 
% disp(summary_table);
% 
% %% ================================================================
% % 10. SAVE RESULTS
% %% ================================================================
% 
% writetable(summary_table,...
%     'Gradient_Optimizer_Test_Performance.xlsx');
% 
% save('Gradient_Optimizer_Results.mat',...
%     'results',...
%     'summary_table',...
%     'X_min','X_max',...
%     'Y_min','Y_max',...
%     'train_idx','val_idx','test_idx',...
%     'time_train','time_val','time_test',...
%     'input_names','output_names',...
%     'n_hidden','n_runs',...
%     'learning_rate','max_epochs','patience');
% 
% fprintf('\nResults saved successfully.\n');
% 
% %% ================================================================
% % 11. BEST OPTIMIZER IDENTIFICATION
% %
% % Average test R2 across all four outputs.
% %% ================================================================
% 
% mean_R2_all = zeros(n_optimizers,1);
% 
% for opt = 1:n_optimizers
% 
%     mean_R2_all(opt) = ...
%         mean(results(opt).R2_test(:));
% 
% end
% 
% [~,best_idx] = max(mean_R2_all);
% 
% fprintf('\n============================================================\n');
% fprintf('BEST GRADIENT OPTIMIZER\n');
% fprintf('============================================================\n');
% 
% fprintf('%s\n',optimizer_names{best_idx});
% fprintf('Mean test R2 across all outputs = %.6f\n',...
%     mean_R2_all(best_idx));
% 
% %% ================================================================
% % 12. R2 COMPARISON PLOT
% %% ================================================================
% 
% figure('Name','Gradient Optimizer R2 Comparison');
% 
% R2_matrix = zeros(n_optimizers,n_outputs_actual);
% 
% for opt = 1:n_optimizers
%     for out = 1:n_outputs_actual
% 
%         R2_matrix(opt,out) = ...
%             mean(results(opt).R2_test(out,:));
% 
%     end
% end
% 
% bar(R2_matrix);
% 
% xlabel('Gradient Optimizer');
% ylabel('Test R^2');
% 
% set(gca,...
%     'XTick',1:n_optimizers,...
%     'XTickLabel',optimizer_names);
% 
% xtickangle(45);
% 
% legend(output_names,...
%     'Location','bestoutside');
% 
% title('Gradient-Based Optimizer Performance');
% 
% box on;
% 
% %% ================================================================
% % 13. RMSE COMPARISON PLOT
% %% ================================================================
% 
% figure('Name','Gradient Optimizer RMSE Comparison');
% 
% RMSE_matrix = zeros(n_optimizers,n_outputs_actual);
% 
% for opt = 1:n_optimizers
%     for out = 1:n_outputs_actual
% 
%         RMSE_matrix(opt,out) = ...
%             mean(results(opt).RMSE_test(out,:));
% 
%     end
% end
% 
% bar(RMSE_matrix);
% 
% xlabel('Gradient Optimizer');
% ylabel('Test RMSE');
% 
% set(gca,...
%     'XTick',1:n_optimizers,...
%     'XTickLabel',optimizer_names);
% 
% xtickangle(45);
% 
% legend(output_names,...
%     'Location','bestoutside');
% 
% title('Gradient-Based Optimizer RMSE');
% 
% box on;
% 
% %% ================================================================
% % 14. ACTUAL VS PREDICTED FOR BEST OPTIMIZER
% %% ================================================================
% 
% for out = 1:n_outputs_actual
% 
%     figure('Name',...
%         ['Actual vs Predicted - ' output_names{out}]);
% 
%     hold on;
% 
%     y_actual = Y_test(:,out);
% 
%     pred = results(best_idx).pred_test{out};
% 
%     scatter(y_actual,pred,...
%         45,'filled');
% 
%     min_val = min([y_actual;pred]);
%     max_val = max([y_actual;pred]);
% 
%     plot([min_val max_val],...
%          [min_val max_val],...
%          'k--',...
%          'LineWidth',2);
% 
%     xlabel('Actual Normalized Output');
%     ylabel('Predicted Normalized Output');
% 
%     title(sprintf( ...
%         'Actual vs Predicted: %s (%s)',...
%         output_names{out},...
%         optimizer_names{best_idx}));
% 
%     legend('Prediction','Ideal y=x',...
%         'Location','best');
% 
%     box on;
%     grid off;
% 
% end
% 
% %% ================================================================
% % 15. TRAIN / VALIDATION / TEST PERFORMANCE
% % ================================================================
% 
% for out = 1:n_outputs_actual
% 
%     figure('Name',...
%         ['Performance - ' output_names{out}]);
% 
%     R2_values = zeros(3,n_optimizers);
% 
%     for opt = 1:n_optimizers
% 
%         R2_values(1,opt) = ...
%             mean(results(opt).R2_train(out,:));
% 
%         R2_values(2,opt) = ...
%             mean(results(opt).R2_val(out,:));
% 
%         R2_values(3,opt) = ...
%             mean(results(opt).R2_test(out,:));
% 
%     end
% 
%     bar(R2_values');
% 
%     xlabel('Gradient Optimizer');
%     ylabel('R^2');
% 
%     set(gca,...
%         'XTick',1:n_optimizers,...
%         'XTickLabel',optimizer_names);
% 
%     xtickangle(45);
% 
%     legend({'Training','Validation','Testing'},...
%         'Location','best');
% 
%     title(['Generalization Performance - ' ...
%         output_names{out}]);
% 
%     box on;
% 
% end
% 
% %% ================================================================
% % 16. NETWORK ARCHITECTURE REPORT
% %% ================================================================
% 
% fprintf('\n============================================================\n');
% fprintf('MODEL ARCHITECTURE AND TRAINING SETTINGS\n');
% fprintf('============================================================\n');
% 
% fprintf('Input layer          : %d neurons\n',n_input);
% fprintf('Hidden layer         : %d neurons\n',n_hidden);
% fprintf('Hidden activation    : %s\n',activation);
% fprintf('Output layer         : 1 neuron\n');
% fprintf('Output activation    : Linear\n');
% fprintf('Learning rate        : %.6f\n',learning_rate);
% fprintf('Maximum epochs       : %d\n',max_epochs);
% fprintf('Early stopping       : %d epochs\n',patience);
% fprintf('Mini-batch size      : %d\n',mini_batch_size);
% fprintf('Independent runs     : %d\n',n_runs);
% fprintf('L2 regularization    : %.6f\n',lambda);
% fprintf('Gradient clipping    : %.2f\n',gradient_clip);
% 
% fprintf('\nData splitting:\n');
% fprintf('Training             : 70%%\n');
% fprintf('Validation           : 15%%\n');
% fprintf('Testing              : 15%%\n');
% 
% fprintf('\nNormalization:\n');
% fprintf('Method               : Min-Max\n');
% fprintf('Parameters estimated : Training set only\n');
% 
% %% ================================================================
% % LOCAL FUNCTIONS
% %% ================================================================
% 
% function net = initialize_network(n_input,n_hidden)
% 
%     % Xavier/Glorot-style initialization
% 
%     limit1 = sqrt(6/(n_input+n_hidden));
% 
%     limit2 = sqrt(6/(n_hidden+1));
% 
%     net.W1 = ...
%         -limit1 + 2*limit1*rand(n_hidden,n_input);
% 
%     net.b1 = zeros(n_hidden,1);
% 
%     net.W2 = ...
%         -limit2 + 2*limit2*rand(1,n_hidden);
% 
%     net.b2 = 0;
% 
% end
% 
% 
% function state = initialize_optimizer_state(net,optimizer)
% 
%     state.vW1 = zeros(size(net.W1));
%     state.vb1 = zeros(size(net.b1));
% 
%     state.vW2 = zeros(size(net.W2));
%     state.vb2 = zeros(size(net.b2));
% 
%     state.mW1 = zeros(size(net.W1));
%     state.mb1 = zeros(size(net.b1));
% 
%     state.mW2 = zeros(size(net.W2));
%     state.mb2 = zeros(size(net.b2));
% 
%     state.sW1 = zeros(size(net.W1));
%     state.sb1 = zeros(size(net.b1));
% 
%     state.sW2 = zeros(size(net.W2));
%     state.sb2 = zeros(size(net.b2));
% 
%     state.t = 0;
% 
%     % Adadelta parameters
%     state.EgW1 = zeros(size(net.W1));
%     state.Egb1 = zeros(size(net.b1));
%     state.EgW2 = zeros(size(net.W2));
%     state.Egb2 = zeros(size(net.b2));
% 
%     state.EdxW1 = zeros(size(net.W1));
%     state.Edxb1 = zeros(size(net.b1));
%     state.EdxW2 = zeros(size(net.W2));
%     state.Edxb2 = zeros(size(net.b2));
% 
% end
% 
% 
% function [yhat,grads] = network_gradient(net,X,y,lambda)
% 
%     % Forward pass
% 
%     Z1 = X*net.W1' + net.b1';
% 
%     A1 = tanh(Z1);
% 
%     yhat = A1*net.W2' + net.b2;
% 
%     % Error
% 
%     n = size(X,1);
% 
%     error = yhat-y;
% 
%     % Output layer gradient
% 
%     dW2 = (2/n)*(error'*A1);
% 
%     db2 = (2/n)*sum(error,1);
% 
%     % Hidden layer
% 
%     dA1 = error*net.W2;
% 
%     dZ1 = dA1.*(1-A1.^2);
% 
%     dW1 = (2/n)*(dZ1'*X);
% 
%     db1 = (2/n)*sum(dZ1,1)';
% 
%     % L2 regularization
% 
%     dW1 = dW1 + lambda*net.W1;
% 
%     dW2 = dW2 + lambda*net.W2;
% 
%     grads.W1 = dW1;
%     grads.b1 = db1;
% 
%     grads.W2 = dW2;
%     grads.b2 = db2;
% 
% end
% 
% 
% function yhat = network_predict(net,X)
% 
%     Z1 = X*net.W1' + net.b1';
% 
%     A1 = tanh(Z1);
% 
%     yhat = A1*net.W2' + net.b2;
% 
% end
% 
% 
% function grads = clip_gradients(grads,clip_value)
% 
%     fields = {'W1','b1','W2','b2'};
% 
%     for i = 1:length(fields)
% 
%         f = fields{i};
% 
%         grads.(f) = max( ...
%             min(grads.(f),clip_value),...
%             -clip_value);
% 
%     end
% 
% end
% 
% 
% function [net,state] = optimizer_update( ...
%     net,state,grads,optimizer,lr,epoch)
% 
%     switch optimizer
% 
%         %% ========================================================
%         % BATCH GRADIENT DESCENT
%         %% ========================================================
% 
%         case 'BGD'
% 
%             net.W1 = net.W1 - lr*grads.W1;
%             net.b1 = net.b1 - lr*grads.b1;
% 
%             net.W2 = net.W2 - lr*grads.W2;
%             net.b2 = net.b2 - lr*grads.b2;
% 
% 
%         %% ========================================================
%         % STOCHASTIC GRADIENT DESCENT
%         %% ========================================================
% 
%         case 'SGD'
% 
%             net.W1 = net.W1 - lr*grads.W1;
%             net.b1 = net.b1 - lr*grads.b1;
% 
%             net.W2 = net.W2 - lr*grads.W2;
%             net.b2 = net.b2 - lr*grads.b2;
% 
% 
%         %% ========================================================
%         % MINI-BATCH GRADIENT DESCENT
%         %% ========================================================
% 
%         case 'MBGD'
% 
%             net.W1 = net.W1 - lr*grads.W1;
%             net.b1 = net.b1 - lr*grads.b1;
% 
%             net.W2 = net.W2 - lr*grads.W2;
%             net.b2 = net.b2 - lr*grads.b2;
% 
% 
%         %% ========================================================
%         % MOMENTUM
%         %% ========================================================
% 
%         case 'Momentum'
% 
%             beta = 0.9;
% 
%             state.vW1 = beta*state.vW1 + lr*grads.W1;
%             state.vb1 = beta*state.vb1 + lr*grads.b1;
% 
%             state.vW2 = beta*state.vW2 + lr*grads.W2;
%             state.vb2 = beta*state.vb2 + lr*grads.b2;
% 
%             net.W1 = net.W1 - state.vW1;
%             net.b1 = net.b1 - state.vb1;
% 
%             net.W2 = net.W2 - state.vW2;
%             net.b2 = net.b2 - state.vb2;
% 
% 
%         %% ========================================================
%         % NESTEROV ACCELERATED GRADIENT
%         %% ========================================================
% 
%         case 'NAG'
% 
%             beta = 0.9;
% 
%             state.vW1 = beta*state.vW1 + lr*grads.W1;
%             state.vb1 = beta*state.vb1 + lr*grads.b1;
% 
%             state.vW2 = beta*state.vW2 + lr*grads.W2;
%             state.vb2 = beta*state.vb2 + lr*grads.b2;
% 
%             net.W1 = net.W1 - state.vW1;
%             net.b1 = net.b1 - state.vb1;
% 
%             net.W2 = net.W2 - state.vW2;
%             net.b2 = net.b2 - state.vb2;
% 
% 
%         %% ========================================================
%         % ADAGRAD
%         %% ========================================================
% 
%         case 'Adagrad'
% 
%             epsilon = 1e-8;
% 
%             state.sW1 = state.sW1 + grads.W1.^2;
%             state.sb1 = state.sb1 + grads.b1.^2;
% 
%             state.sW2 = state.sW2 + grads.W2.^2;
%             state.sb2 = state.sb2 + grads.b2.^2;
% 
%             net.W1 = net.W1 - ...
%                 lr*grads.W1./sqrt(state.sW1+epsilon);
% 
%             net.b1 = net.b1 - ...
%                 lr*grads.b1./sqrt(state.sb1+epsilon);
% 
%             net.W2 = net.W2 - ...
%                 lr*grads.W2./sqrt(state.sW2+epsilon);
% 
%             net.b2 = net.b2 - ...
%                 lr*grads.b2./sqrt(state.sb2+epsilon);
% 
% 
%         %% ========================================================
%         % RMSPROP
%         %% ========================================================
% 
%         case 'RMSProp'
% 
%             beta = 0.9;
%             epsilon = 1e-8;
% 
%             state.sW1 = beta*state.sW1 + ...
%                 (1-beta)*grads.W1.^2;
% 
%             state.sb1 = beta*state.sb1 + ...
%                 (1-beta)*grads.b1.^2;
% 
%             state.sW2 = beta*state.sW2 + ...
%                 (1-beta)*grads.W2.^2;
% 
%             state.sb2 = beta*state.sb2 + ...
%                 (1-beta)*grads.b2.^2;
% 
%             net.W1 = net.W1 - ...
%                 lr*grads.W1./sqrt(state.sW1+epsilon);
% 
%             net.b1 = net.b1 - ...
%                 lr*grads.b1./sqrt(state.sb1+epsilon);
% 
%             net.W2 = net.W2 - ...
%                 lr*grads.W2./sqrt(state.sW2+epsilon);
% 
%             net.b2 = net.b2 - ...
%                 lr*grads.b2./sqrt(state.sb2+epsilon);
% 
% 
%         %% ========================================================
%         % ADADELTA
%         %% ========================================================
% 
%         case 'Adadelta'
% 
%             rho = 0.95;
%             epsilon = 1e-6;
% 
%             state.EgW1 = rho*state.EgW1 + ...
%                 (1-rho)*grads.W1.^2;
% 
%             state.Egb1 = rho*state.Egb1 + ...
%                 (1-rho)*grads.b1.^2;
% 
%             state.EgW2 = rho*state.EgW2 + ...
%                 (1-rho)*grads.W2.^2;
% 
%             state.Egb2 = rho*state.Egb2 + ...
%                 (1-rho)*grads.b2.^2;
% 
%             dW1 = -sqrt(state.EdxW1+epsilon) ...
%                 ./sqrt(state.EgW1+epsilon).*grads.W1;
% 
%             db1 = -sqrt(state.Edxb1+epsilon) ...
%                 ./sqrt(state.Egb1+epsilon).*grads.b1;
% 
%             dW2 = -sqrt(state.EdxW2+epsilon) ...
%                 ./sqrt(state.EgW2+epsilon).*grads.W2;
% 
%             db2 = -sqrt(state.Edxb2+epsilon) ...
%                 ./sqrt(state.Egb2+epsilon).*grads.b2;
% 
%             state.EdxW1 = rho*state.EdxW1 + ...
%                 (1-rho)*dW1.^2;
% 
%             state.Edxb1 = rho*state.Edxb1 + ...
%                 (1-rho)*db1.^2;
% 
%             state.EdxW2 = rho*state.EdxW2 + ...
%                 (1-rho)*dW2.^2;
% 
%             state.Edxb2 = rho*state.Edxb2 + ...
%                 (1-rho)*db2.^2;
% 
%             net.W1 = net.W1 + dW1;
%             net.b1 = net.b1 + db1;
% 
%             net.W2 = net.W2 + dW2;
%             net.b2 = net.b2 + db2;
% 
% 
%         %% ========================================================
%         % ADAMAX
%         %% ========================================================
% 
%         case 'Adamax'
% 
%             beta1 = 0.9;
%             beta2 = 0.999;
%             epsilon = 1e-8;
% 
%             state.t = state.t + 1;
% 
%             % First moment
% 
%             state.mW1 = beta1*state.mW1 + ...
%                 (1-beta1)*grads.W1;
% 
%             state.mb1 = beta1*state.mb1 + ...
%                 (1-beta1)*grads.b1;
% 
%             state.mW2 = beta1*state.mW2 + ...
%                 (1-beta1)*grads.W2;
% 
%             state.mb2 = beta1*state.mb2 + ...
%                 (1-beta1)*grads.b2;
% 
%             % Infinity norm
% 
%             state.sW1 = max( ...
%                 beta2*state.sW1,...
%                 abs(grads.W1));
% 
%             state.sb1 = max( ...
%                 beta2*state.sb1,...
%                 abs(grads.b1));
% 
%             state.sW2 = max( ...
%                 beta2*state.sW2,...
%                 abs(grads.W2));
% 
%             state.sb2 = max( ...
%                 beta2*state.sb2,...
%                 abs(grads.b2));
% 
%             alpha_t = lr/(1-beta1^state.t);
% 
%             net.W1 = net.W1 - ...
%                 alpha_t*state.mW1./(state.sW1+epsilon);
% 
%             net.b1 = net.b1 - ...
%                 alpha_t*state.mb1./(state.sb1+epsilon);
% 
%             net.W2 = net.W2 - ...
%                 alpha_t*state.mW2./(state.sW2+epsilon);
% 
%             net.b2 = net.b2 - ...
%                 alpha_t*state.mb2./(state.sb2+epsilon);
% 
%     end
% 
% end
% 
% 
% function [R2,RMSE,MAE,MSE] = calculate_metrics(y,yhat)
% 
%     residual = y-yhat;
% 
%     MSE = mean(residual.^2);
% 
%     RMSE = sqrt(MSE);
% 
%     MAE = mean(abs(residual));
% 
%     denominator = ...
%         sum((y-mean(y)).^2);
% 
%     if denominator == 0
% 
%         R2 = NaN;
% 
%     else
% 
%         R2 = 1 - ...
%             sum(residual.^2)/denominator;
% 
%     end
% 
% end



%%

%%

clear; clc; close all;

%% GLOBAL STYLE
set(groot,'defaultAxesFontSize',26);
set(groot,'defaultAxesFontWeight','bold');
set(groot,'defaultLineLineWidth',3);
set(groot,'defaultLineMarkerSize',8);

%% SAVE PATH
base_path = 'F:\PhD matlab\MATLAB\my research\improved code protease\1to 8 equation 3d hydrodynamics atpes\1-8 equan along with my fermentation interaction\ML';
save_path_all = fullfile(base_path, 'combined_figures_gradient');

if ~exist(save_path_all,'dir')
    try
        mkdir(save_path_all);
    catch ME
        warning('Could not create "%s" (%s). Saving figures to a local folder instead.', ...
            save_path_all, ME.message);
        save_path_all = fullfile(pwd, 'combined_figures_gradient');
        if ~exist(save_path_all,'dir')
            mkdir(save_path_all);
        end
    end
end
fprintf('Figures will be saved to: %s\n', save_path_all);

%% ========================================================================
% MULTI-RUN SETTINGS
% ========================================================================
%
% To address the reviewer comment on single-run reporting, the entire
% split -> normalize -> train -> evaluate pipeline below is repeated
% n_runs times, each with an independent random train/val/test split
% and independent weight initialization (rng(seed) reseeds everything,
% including the SGD/MBGD stochastic sampling and Adam-family updates).
% Performance is reported as mean +/- std across runs.
%
% NOTE ON RUNTIME: each run repeats the full alpha-grid search
% (length(alphas) candidates) for all 9 methods x 4 outputs, up to
% 10,000 epochs each. n_runs = 10 will therefore take roughly 10x as
% long as a single run. Reduce n_runs (e.g. to 3-5) for a quick check,
% or reduce `epochs`/`alphas` length for the multi-run study and use
% the full grid only for the final reported model.
% ========================================================================

n_runs = 10;
seeds  = 0:(n_runs-1);

%% 1. LOAD DATA
data_file = fullfile(base_path, 'process_data.xlsx');
if ~isfile(data_file)
    error(['Could not find "%s".\n' ...
           'Move/copy process_data.xlsx into that folder, or update ' ...
           '"base_path" at the top of the script to wherever the file ' ...
           'actually lives.'], data_file);
end
data = readtable(data_file);

X_raw = table2array(data(:, {'x2','x4','x5'}));
Y_raw = table2array(data(:, {'y_fermentation','y_interaction','y_top_phase','y_bottom_phase'}));

n_obs = size(X_raw,1);

%% 3. SETTINGS
methods = {'GD','SGD','MBGD','Momentum','NAG','Adagrad','RMSProp','Adadelta','Adamax'};
alphas = logspace(-5,-3.2,10);

epochs = 10000;
batch_size = 32;
patience = 500;

n_methods = length(methods);
n_out = size(Y_raw,2);

datasets = {'Training','Validation','Test'};
output_names = {'y_fermentation','y_interaction',...
                'y_top_phase','y_bottom_phase'};
input_names = {'x2','x4','x5'};

%% ========================================================================
% CROSS-RUN STORAGE
% ========================================================================
% metrics_allruns(run, method, output, dataset, metric)
%   dataset: 1=Train, 2=Val, 3=Test
%   metric : 1=R2, 2=RMSE, 3=MAE
metrics_allruns = zeros(n_runs, n_methods, n_out, 3, 3);

convergence_epoch_allruns = zeros(n_runs, n_out, n_methods);
convergence_mse_allruns   = zeros(n_runs, n_out, n_methods);

% Rank of each method per output, per run, based on TEST R2
% (rank 1 = best / highest R2)
rank_testR2_allruns = zeros(n_runs, n_out, n_methods);

% Final weights/bias per run (for mean +/- std reporting)
% dims: (run, weight_index[1:3], output, method)
final_w_allruns = zeros(n_runs, 3, n_out, n_methods);
final_b_allruns = zeros(n_runs, n_out, n_methods);

% Data + results from run 1 are retained for the diagnostic plots below
% (plotting every run separately would produce n_runs x as many figures).
run1_saved = struct();

%% ========================================================================
% MULTI-RUN LOOP
% ========================================================================

for run = 1:n_runs

    seed = seeds(run);
    rng(seed);

    fprintf('\n\n############################################################\n');
    fprintf('RUN %d/%d (seed = %d)\n', run, n_runs, seed);
    fprintf('############################################################\n');

    %% ---- 2. SPLIT RAW DATA FIRST (no leakage into normalization) ----
    idx = randperm(n_obs);

    n_train = floor(0.7*n_obs);
    n_val   = floor(0.15*n_obs);

    train_idx = idx(1:n_train);
    val_idx   = idx(n_train+1:n_train+n_val);
    test_idx  = idx(n_train+n_val+1:end);

    X_train_raw = X_raw(train_idx,:);
    Y_train_raw = Y_raw(train_idx,:);

    X_val_raw = X_raw(val_idx,:);
    Y_val_raw = Y_raw(val_idx,:);

    X_test_raw = X_raw(test_idx,:);
    Y_test_raw = Y_raw(test_idx,:);

    %% ---- NORMALIZE USING TRAINING-SET STATISTICS ONLY ----
    X_min = min(X_train_raw,[],1);
    X_max = max(X_train_raw,[],1);
    X_range = X_max - X_min;
    X_range(X_range==0) = 1;

    Y_min = min(Y_train_raw,[],1);
    Y_max = max(Y_train_raw,[],1);
    Y_range = Y_max - Y_min;
    Y_range(Y_range==0) = 1;

    X_train = (X_train_raw - X_min) ./ X_range;
    X_val   = (X_val_raw   - X_min) ./ X_range;
    X_test  = (X_test_raw  - X_min) ./ X_range;

    Y_train = (Y_train_raw - Y_min) ./ Y_range;
    Y_val   = (Y_val_raw   - Y_min) ./ Y_range;
    Y_test  = (Y_test_raw  - Y_min) ./ Y_range;

    %% ---- STORAGE FOR THIS RUN ----
    y_pred_train_all = zeros(size(X_train,1), n_out, n_methods);
    y_pred_val_all   = zeros(size(X_val,1), n_out, n_methods);
    y_pred_test_all  = zeros(size(X_test,1), n_out, n_methods);

    mse_train_hist_best = cell(n_out,n_methods);
    mse_val_hist_best   = cell(n_out,n_methods);
    mse_test_hist_best  = cell(n_out,n_methods);

    w_hist_best = cell(n_out,n_methods);
    b_hist_best = cell(n_out,n_methods);

    final_w = zeros(3,n_out,n_methods);
    final_b = zeros(n_out,n_methods);

    convergence_epoch = zeros(n_out,n_methods);
    convergence_mse   = zeros(n_out,n_methods);

    %% ---- 4. TRAINING ----
    for m = 1:n_methods
        method = methods{m};
        fprintf('\nTraining %s...\n', method);

        for out = 1:n_out

            y_tr = Y_train(:,out);
            y_v  = Y_val(:,out);
            y_te = Y_test(:,out);

            best_val_global = inf;

            for a = 1:length(alphas)
                alpha = alphas(a);

                w = zeros(3,1); b = 0;
                m_w = zeros(3,1); v_w = zeros(3,1);
                m_b = 0; v_b = 0;

                mse_tr = zeros(epochs,1);
                mse_va = zeros(epochs,1);
                mse_te = zeros(epochs,1);
                w_hist = zeros(3,epochs);
                b_hist = zeros(1,epochs);

                best_val_local = inf;
                patience_cnt = 0;

                for ep = 1:epochs

                    y_hat = X_train*w + b;
                    err = y_hat - y_tr;

                    grad_w = (2/length(y_tr))*(X_train'*err);
                    grad_b = (2/length(y_tr))*sum(err);

                    switch method
                        case 'GD'
                            w = w - alpha*grad_w; b = b - alpha*grad_b;
                        case 'SGD'
                            i = randi(length(y_tr));
                            xi = X_train(i,:)';
                            ei = (xi'*w+b)-y_tr(i);
                            w = w - alpha*(2*ei*xi); b = b - alpha*(2*ei);
                        case 'MBGD'
                            id = randperm(length(y_tr), batch_size);
                            Xb = X_train(id,:); yb = y_tr(id);
                            errb = Xb*w+b-yb;
                            w = w - alpha*(2/batch_size)*(Xb'*errb);
                            b = b - alpha*(2/batch_size)*sum(errb);
                        case 'Momentum'
                            m_w = 0.9*m_w + grad_w; m_b = 0.9*m_b + grad_b;
                            w = w - alpha*m_w; b = b - alpha*m_b;
                        case 'NAG'
                            look_w = w - 0.9*m_w; look_b = b - 0.9*m_b;
                            err_l = X_train*look_w+look_b-y_tr;
                            g_w = (2/length(y_tr))*(X_train'*err_l);
                            g_b = (2/length(y_tr))*sum(err_l);
                            m_w = 0.9*m_w + g_w; m_b = 0.9*m_b + g_b;
                            w = w - alpha*m_w; b = b - alpha*m_b;
                        case 'Adagrad'
                            v_w = v_w + grad_w.^2; v_b = v_b + grad_b.^2;
                            w = w - alpha*grad_w./(sqrt(v_w)+1e-8);
                            b = b - alpha*grad_b./(sqrt(v_b)+1e-8);
                        case 'RMSProp'
                            v_w = 0.9*v_w + 0.1*grad_w.^2;
                            v_b = 0.9*v_b + 0.1*grad_b.^2;
                            w = w - alpha*grad_w./(sqrt(v_w)+1e-8);
                            b = b - alpha*grad_b./(sqrt(v_b)+1e-8);
                        case 'Adadelta'
                            v_w = 0.95*v_w + 0.05*grad_w.^2;
                            v_b = 0.95*v_b + 0.05*grad_b.^2;
                            w = w - grad_w./(sqrt(v_w)+1e-8);
                            b = b - grad_b./(sqrt(v_b)+1e-8);
                        case 'Adamax'
                            m_w = 0.9*m_w + 0.1*grad_w;
                            m_b = 0.9*m_b + 0.1*grad_b;
                            v_w = max(0.999*v_w, abs(grad_w));
                            v_b = max(0.999*v_b, abs(grad_b));
                            w = w - alpha*m_w./(v_w+1e-8);
                            b = b - alpha*m_b./(v_b+1e-8);
                    end

                    mse_tr(ep) = mean((X_train*w+b - y_tr).^2);
                    mse_va(ep) = mean((X_val*w+b - y_v).^2);
                    mse_te(ep) = mean((X_test*w+b - y_te).^2);

                    w_hist(:,ep) = w;
                    b_hist(ep) = b;

                    if mse_va(ep) < best_val_local
                        best_val_local = mse_va(ep);
                        best_w = w; best_b = b;
                        best_ep = ep;
                        best_w_hist = w_hist(:,1:ep);
                        best_b_hist = b_hist(1:ep);
                        best_hist_tr = mse_tr(1:ep);
                        best_hist_va = mse_va(1:ep);
                        best_hist_te = mse_te(1:ep);
                        patience_cnt = 0;
                    else
                        patience_cnt = patience_cnt + 1;
                        if patience_cnt > patience, break; end
                    end
                end

                if best_val_local < best_val_global
                    best_val_global = best_val_local;

                    best_w_final = best_w;
                    best_b_final = best_b;

                    final_wh = best_w_hist;
                    final_bh = best_b_hist;
                    final_tr = best_hist_tr;
                    final_va = best_hist_va;
                    final_te = best_hist_te;
                    final_ep = best_ep;
                end
            end

            final_w(:,out,m) = best_w_final;
            final_b(out,m) = best_b_final;

            convergence_epoch(out,m) = final_ep;
            convergence_mse(out,m) = best_val_global;

            w_hist_best{out,m} = final_wh;
            b_hist_best{out,m} = final_bh;
            mse_train_hist_best{out,m} = final_tr;
            mse_val_hist_best{out,m}   = final_va;
            mse_test_hist_best{out,m}  = final_te;

            y_pred_train_all(:,out,m) = X_train*best_w_final + best_b_final;
            y_pred_val_all(:,out,m)   = X_val*best_w_final + best_b_final;
            y_pred_test_all(:,out,m)  = X_test*best_w_final + best_b_final;
        end

    end

    %% ---- METRICS FOR THIS RUN ----
    for m = 1:n_methods
        for out = 1:n_out

            % TRAIN
            y = Y_train(:,out);
            yhat = y_pred_train_all(:,out,m);
            R2 = 1 - sum((y-yhat).^2)/sum((y-mean(y)).^2);
            RMSE = sqrt(mean((y-yhat).^2));
            MAE = mean(abs(y-yhat));
            metrics_allruns(run,m,out,1,:) = [R2 RMSE MAE];

            % VALIDATION
            y = Y_val(:,out);
            yhat = y_pred_val_all(:,out,m);
            R2 = 1 - sum((y-yhat).^2)/sum((y-mean(y)).^2);
            RMSE = sqrt(mean((y-yhat).^2));
            MAE = mean(abs(y-yhat));
            metrics_allruns(run,m,out,2,:) = [R2 RMSE MAE];

            % TEST
            y = Y_test(:,out);
            yhat = y_pred_test_all(:,out,m);
            R2 = 1 - sum((y-yhat).^2)/sum((y-mean(y)).^2);
            RMSE = sqrt(mean((y-yhat).^2));
            MAE = mean(abs(y-yhat));
            metrics_allruns(run,m,out,3,:) = [R2 RMSE MAE];

        end
    end

    convergence_epoch_allruns(run,:,:) = convergence_epoch;
    convergence_mse_allruns(run,:,:)   = convergence_mse;

    final_w_allruns(run,:,:,:) = final_w;
    final_b_allruns(run,:,:)   = final_b;

    % Rank methods per output by TEST R2 (1 = best)
    for out = 1:n_out
        test_R2_this_run = squeeze(metrics_allruns(run,:,out,3,1));
        [~,order] = sort(test_R2_this_run,'descend');
        ranks = zeros(1,n_methods);
        ranks(order) = 1:n_methods;
        rank_testR2_allruns(run,out,:) = ranks;
    end

    if run == 1
        run1_saved.X_train = X_train;
        run1_saved.X_val   = X_val;
        run1_saved.X_test  = X_test;
        run1_saved.Y_train = Y_train;
        run1_saved.Y_val   = Y_val;
        run1_saved.Y_test  = Y_test;
        run1_saved.y_pred_train_all = y_pred_train_all;
        run1_saved.y_pred_val_all   = y_pred_val_all;
        run1_saved.y_pred_test_all  = y_pred_test_all;
        run1_saved.mse_train_hist_best = mse_train_hist_best;
        run1_saved.mse_val_hist_best   = mse_val_hist_best;
        run1_saved.mse_test_hist_best  = mse_test_hist_best;
        run1_saved.w_hist_best = w_hist_best;
        run1_saved.b_hist_best = b_hist_best;
        run1_saved.final_w = final_w;
        run1_saved.final_b = final_b;
        run1_saved.convergence_epoch = convergence_epoch;
        run1_saved.convergence_mse = convergence_mse;
    end

end

%% ========================================================================
% AGGREGATE ACROSS RUNS: MEAN +/- STD
% ========================================================================

metrics_mean = squeeze(mean(metrics_allruns,1));  % (method, output, dataset, metric)
metrics_std  = squeeze(std(metrics_allruns,0,1));

metric_names = {'R2','RMSE','MAE'};

fprintf('\n\n============================================================\n');
fprintf(' PERFORMANCE ACROSS %d INDEPENDENT RUNS (MEAN +/- STD)\n', n_runs);
fprintf('============================================================\n');

MultiRunTable = table;

for m = 1:n_methods
    for out = 1:n_out
        for d = 1:3

            R2_mean = metrics_mean(m,out,d,1); R2_std = metrics_std(m,out,d,1);
            RMSE_mean = metrics_mean(m,out,d,2); RMSE_std = metrics_std(m,out,d,2);
            MAE_mean = metrics_mean(m,out,d,3); MAE_std = metrics_std(m,out,d,3);

            MultiRunTable = [MultiRunTable;
                table({methods{m}}, output_names(out), datasets(d), ...
                R2_mean, R2_std, RMSE_mean, RMSE_std, MAE_mean, MAE_std, ...
                'VariableNames',{'Method','Output','Dataset', ...
                'R2_mean','R2_std','RMSE_mean','RMSE_std','MAE_mean','MAE_std'})]; %#ok<AGROW>

        end
    end
end

disp(MultiRunTable);

fprintf('\nTest-set summary (mean +/- std over %d runs):\n', n_runs);
for out = 1:n_out
    fprintf('\n--- Output: %s ---\n', output_names{out});
    for m = 1:n_methods
        fprintf('  %-10s : R2 = %.4f +/- %.4f | RMSE = %.4f +/- %.4f | MAE = %.4f +/- %.4f\n', ...
            methods{m}, ...
            metrics_mean(m,out,3,1), metrics_std(m,out,3,1), ...
            metrics_mean(m,out,3,2), metrics_std(m,out,3,2), ...
            metrics_mean(m,out,3,3), metrics_std(m,out,3,3));
    end
end

%% ========================================================================
% RANKING STABILITY (TEST R2)
% ========================================================================
% Demonstrates whether the relative ordering of methods is consistent
% across independent runs -- rank 1 = best (highest test R2) in a given
% run. A low std of rank indicates a stable/robust ranking; a high std
% indicates the ranking is sensitive to the particular train/val/test
% split and initialization.

rank_mean = squeeze(mean(rank_testR2_allruns,1)); % (output, method)
rank_std  = squeeze(std(rank_testR2_allruns,0,1));

fprintf('\n\n============================================================\n');
fprintf(' RANKING STABILITY ACROSS %d RUNS (based on Test R2, 1 = best)\n', n_runs);
fprintf('============================================================\n');

RankingTable = table;

for out = 1:n_out
    fprintf('\n--- Output: %s ---\n', output_names{out});

    [~,order] = sort(rank_mean(out,:),'ascend');

    for k = 1:n_methods
        m = order(k);
        fprintf('  %-10s : mean rank = %.2f +/- %.2f\n', ...
            methods{m}, rank_mean(out,m), rank_std(out,m));

        RankingTable = [RankingTable;
            table({methods{m}}, output_names(out), ...
            rank_mean(out,m), rank_std(out,m), ...
            'VariableNames',{'Method','Output','MeanRank','StdRank'})]; %#ok<AGROW>
    end
end

fprintf(['\nNOTE: mean/std rank is computed within each output across the ' ...
    '%d runs; a std near 0 indicates that method consistently occupies ' ...
    'the same relative position regardless of the random split/seed.\n'], n_runs);

%% ========================================================================
% CONVERGENCE (AGGREGATED)
% ========================================================================

fprintf('\n==== CONVERGENCE (MEAN +/- STD OVER %d RUNS) ====\n', n_runs);

conv_epoch_mean = squeeze(mean(convergence_epoch_allruns,1));
conv_epoch_std  = squeeze(std(convergence_epoch_allruns,0,1));
conv_mse_mean   = squeeze(mean(convergence_mse_allruns,1));
conv_mse_std    = squeeze(std(convergence_mse_allruns,0,1));

conv_table = table;

for m = 1:n_methods
    for out = 1:n_out

        conv_table = [conv_table;
            table({methods{m}}, output_names(out), ...
            conv_epoch_mean(out,m), conv_epoch_std(out,m), ...
            conv_mse_mean(out,m), conv_mse_std(out,m), ...
            'VariableNames',{'Method','Output','Epoch_mean','Epoch_std', ...
            'Best_MSE_mean','Best_MSE_std'})]; %#ok<AGROW>
    end
end

disp(conv_table);

%% ================= FINAL WEIGHTS & BIAS (MEAN +/- STD OVER ALL RUNS) =================
fprintf('\n==== FINAL WEIGHTS & BIAS (MEAN +/- STD OVER %d RUNS) ====\n', n_runs);

w_mean = squeeze(mean(final_w_allruns,1));  % (3, output, method)
w_std  = squeeze(std(final_w_allruns,0,1));
b_mean = squeeze(mean(final_b_allruns,1));  % (output, method)
b_std  = squeeze(std(final_b_allruns,0,1));

wb_table = table;

for m = 1:n_methods
    for out = 1:n_out

        w1_mean = w_mean(1,out,m); w1_std = w_std(1,out,m);
        w2_mean = w_mean(2,out,m); w2_std = w_std(2,out,m);
        w3_mean = w_mean(3,out,m); w3_std = w_std(3,out,m);
        bias_mean = b_mean(out,m); bias_std = b_std(out,m);

        wb_table = [wb_table;
            table({methods{m}}, output_names(out), ...
            w1_mean, w1_std, w2_mean, w2_std, w3_mean, w3_std, bias_mean, bias_std, ...
            'VariableNames',{'Method','Output', ...
            'w1_mean','w1_std','w2_mean','w2_std','w3_mean','w3_std', ...
            'Bias_mean','Bias_std'})]; %#ok<AGROW>
    end
end

disp(wb_table);

fprintf('\nFinal weights/bias (mean +/- std over %d runs):\n', n_runs);
for out = 1:n_out
    fprintf('\n--- Output: %s ---\n', output_names{out});
    for m = 1:n_methods
        fprintf('  %-10s : w1 = %8.4f +/- %.4f | w2 = %8.4f +/- %.4f | w3 = %8.4f +/- %.4f | b = %8.4f +/- %.4f\n', ...
            methods{m}, ...
            w_mean(1,out,m), w_std(1,out,m), ...
            w_mean(2,out,m), w_std(2,out,m), ...
            w_mean(3,out,m), w_std(3,out,m), ...
            b_mean(out,m), b_std(out,m));
    end
end

%% ================= PLOTTING (REPRESENTATIVE: RUN 1) =================
fprintf(['\nNOTE: The figures below are generated from Run 1 (seed = %d) only, ' ...
    'as a representative diagnostic. Reported numeric performance above ' ...
    '(mean +/- std) reflects all %d independent runs.\n'], seeds(1), n_runs);

X_train = run1_saved.X_train;
X_val   = run1_saved.X_val;
X_test  = run1_saved.X_test;
Y_train = run1_saved.Y_train;
Y_val   = run1_saved.Y_val;
Y_test  = run1_saved.Y_test;

y_pred_train_all = run1_saved.y_pred_train_all;
y_pred_val_all   = run1_saved.y_pred_val_all;
y_pred_test_all  = run1_saved.y_pred_test_all;

mse_train_hist_best = run1_saved.mse_train_hist_best;
mse_val_hist_best   = run1_saved.mse_val_hist_best;
mse_test_hist_best  = run1_saved.mse_test_hist_best;

w_hist_best = run1_saved.w_hist_best;
b_hist_best = run1_saved.b_hist_best;

colors = lines(n_methods);
markers = {'o','s','d','^','v','>','<','p','h'};

Y_sets = {Y_train, Y_val, Y_test};
Y_pred_sets = {y_pred_train_all, y_pred_val_all, y_pred_test_all};
X_sets = {X_train, X_val, X_test};

% MSE PLOTS
for d = 1:3
    figure; hold on;
    for m = 1:n_methods
        mse = mse_train_hist_best{1,m};
        if d==2, mse = mse_val_hist_best{1,m}; end
        if d==3, mse = mse_test_hist_best{1,m}; end
        if isempty(mse), continue; end

        plot(mse,'Color',colors(m,:),'Marker',markers{m},...
            'MarkerIndices',round(linspace(1,length(mse),10)),...
            'DisplayName',methods{m});
    end
    set(gca,'YScale','log','LineWidth',3); box on;
    xlabel('Epoch'); ylabel('MSE'); title(datasets{d});
    legend show;
    % SAVE
    save_myfig(save_path_all, sprintf('MSE_%s', datasets{d}));
end

for d = 1:3
    for out = 1:n_out

        figure; hold on;

        for m = 1:n_methods

            scatter(Y_sets{d}(:,out), ...
                    Y_pred_sets{d}(:,out,m), ...
                    64, ...
                    markers{m}, ...
                    'MarkerEdgeColor', colors(m,:), ...
                    'LineWidth', 1.5, ...
                    'DisplayName', methods{m});
        end

        % Ideal line
        plot([0 1],[0 1], 'k--', 'LineWidth', 3, 'DisplayName','Ideal');

        % Styling
        set(gca, 'LineWidth', 3);
        box on;

        xlabel('Actual');
        ylabel('Predicted');

        title(sprintf('%s - %s (Run 1)', datasets{d}, output_names{out}));

        legend show;

        % Save
        save_myfig(save_path_all, ...
            sprintf('Actual_vs_Predicted_%s_%s', datasets{d}, output_names{out}));
    end
end
%% ================= INPUT vs OUTPUT =================
for d = 1:3
    for in = 1:3
        for out = 1:4

            figure; hold on;

            Xd = X_sets{d};
            Yd = Y_sets{d};
            Ypd = Y_pred_sets{d};

            % Sort to avoid zig-zag
            [xs, idxs] = sort(Xd(:,in));

            % Actual
            scatter(xs, Yd(idxs,out), 60, 'k', 'filled', ...
                'DisplayName','Actual');

            % Predictions
            for m = 1:n_methods
                yp = Ypd(:,out,m);

                plot(xs, yp(idxs), ...
                    'Color', colors(m,:), ...
                    'LineWidth',3, ...
                    'DisplayName', methods{m});
            end

            set(gca,'LineWidth',3);
            box on;
            xlabel(input_names{in});
            ylabel(output_names{out});
            title(sprintf('%s: %s vs %s (Run 1)', ...
                datasets{d}, input_names{in}, output_names{out}));

            legend show;
             save_myfig(save_path_all,...
                sprintf('Input_%s_vs_%s_%s',input_names{in},output_names{out},datasets{d}));
        end
    end

end
%% ================= 3D FINAL PLOTS =================
colors_out = lines(n_out);

for m = 1:n_methods

    figure; hold on;

    for out = 1:n_out

        wh = w_hist_best{out,m};
        bh = b_hist_best{out,m};
        mse = mse_train_hist_best{out,m};

        if isempty(wh), continue; end

        ep = 1:length(mse);

        mse_n = mse / max(mse);
        w1 = wh(1,:) / max(abs(wh(1,:)));
        w2 = wh(2,:) / max(abs(wh(2,:)));
        w3 = wh(3,:) / max(abs(wh(3,:)));
        b  = bh / max(abs(bh));

        c = colors_out(out,:);

        plot3(mse_n, ep, w1, '-',  'Color',c,'DisplayName',sprintf('Out%d-w1',out));
        plot3( mse_n, ep, w2, '--', 'Color',c,'DisplayName',sprintf('Out%d-w2',out));
        plot3( mse_n, ep, w3, ':',  'Color',c,'DisplayName',sprintf('Out%d-w3',out));
        plot3(mse_n, ep, b, '-.', 'Color',c,'DisplayName',sprintf('Out%d-b',out));
    end

    set(gca,'LineWidth',3);
    box on;
    view(135,25);

    ylabel('Epoch');
    zlabel('Weights / Bias');
    xlabel('MSE');

    title(sprintf('%s (Run 1)', methods{m}));
    legend('Location','bestoutside');

    % SAVE
    save_myfig(save_path_all, sprintf('MSE_Run1_%s', methods{m}));
end

%% ========================================================================
% LOCAL FUNCTIONS
% ========================================================================

function save_myfig(save_path, name)
    savefig(gcf, fullfile(save_path, [name '.fig']));
    saveas(gcf, fullfile(save_path, [name '.png']));
end