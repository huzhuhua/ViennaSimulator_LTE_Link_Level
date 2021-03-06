function [rank_i,PMI,CQI] =  LTE_feedback_CLSM(nAtPort,sigma_n2,LTE_params,channel,UE,uu)
% author Stefan Schwarz
% contact stefan.schwarz@nt.tuwien.ac.at
% calculates the PMI, RI and CQI feedback

%% channel prediction
% save channel matrix for channel prediction 
UE.previous_channels = circshift(UE.previous_channels,[0,0,-1,0,0]);
UE.previous_channels(:,:,end,:,:)=channel(:,:,:,:);
H_est_complete = LTE_channel_predictor(UE.previous_channels,LTE_params.uplink_delay,LTE_params.ChanMod_config.filtering,UE.predict);

%% some initializations
% rank_i = min(size(H_est_complete,3),size(H_est_complete,4));    % NOTE: remove when rank_i feedback is supported!
H = reshape(mean(mean(H_est_complete,1),2),size(H_est_complete,3),size(H_est_complete,4)); 
max_rank = min(size(H));
PMI = zeros(LTE_params.Nrb,2);
PMI_temp = zeros(max_rank,LTE_params.Nrb,2);
% CQI = zeros(LTE_params.Nrb,2,min(2,max_rank));
% CQI_temp = zeros(LTE_params.Nrb,2,max_rank,min(2,max_rank));
CQI = zeros(LTE_params.Nrb,2,max_rank);
CQI_temp = zeros(LTE_params.Nrb,2,max_rank,max_rank);


if nAtPort == 2 
    i_max = [3,2];
%     i_max = [1,1];
else
    i_max = [15,15,15,15];
end

if LTE_params.feedback.channel_averaging % use channel averaging
    RB_max = LTE_params.Nrb;
    I_g = zeros(max(i_max)+1,max_rank,RB_max,2);   % total sum rate over all resource blocks 
    SNR_g = zeros(max(i_max)+1,max_rank,RB_max,2,4); 
else
    gran = 4;
    RB_max = LTE_params.Nrb*gran;
    I_g = zeros(max(i_max)+1,max_rank,RB_max,2);   % total sum rate over all resource blocks 
    SNR_g = zeros(max(i_max)+1,max_rank,RB_max,2,4); 
end
% figure(1)
% clf
I_RB = zeros(max(i_max)+1,max_rank);   
for RB_i = 1:RB_max
    for slot_i = 1:2  
        if LTE_params.feedback.channel_averaging
            freq_band = (RB_i-1)*LTE_params.Nsc+1:min(RB_i*LTE_params.Nsc,size(H_est_complete,1));
        else
            freq_band = round(((RB_i-1)*LTE_params.Nsc/gran+1+min(RB_i*LTE_params.Nsc/gran,size(H_est_complete,1)))/2);
        end
        H_est = H_est_complete(freq_band,(slot_i-1)*LTE_params.Ns+1:slot_i*LTE_params.Ns,:,:);
        
        if UE.RIandPMI_fb % wheter RI and PMI feedback is activated 
            rank_loop = 1:max_rank;
        else    % iterate only over the actual RI value if RI feedback is deactivated         
            rank_loop = LTE_params.scheduler.nLayers(uu);
        end
%         rank_loop = 4;
        H_t = reshape(mean(mean(H_est,1),2),size(H_est,3),size(H_est,4));   % Channel of current RB and slot 
        if ~LTE_params.feedback.ignore_channel_estimation % channel estimation error will be ignored if set so
            MSE_mean = mean(UE.MSE(:,freq_band),2);                         % Channel estimator MSE 
        else
            MSE_mean = zeros(size(UE.MSE,1),1);
        end
        I = zeros(max(i_max)+1,max_rank);   
        SNR = zeros(max(i_max)+1,max(rank_loop),max(rank_loop));
        for rr = rank_loop    % Iterate over all possible layer numbers, to find the one that delivers the maximum sum rate   
            if rr == 2 && nAtPort == 2 
                i_start = 1;
                i_stop = i_max(rr);
            else
                i_start = 0;
                i_stop = i_max(rr);
            end
            for i = i_start:i_stop
                [Z W U D] = LTE_common_get_precoding_matrix(4,nAtPort,i,rr,LTE_params);
                P = H_t*W;
                switch LTE_params.UE_config.receiver 
%                   switch 'ZF'
                    case 'ZF'
                        F = pinv(P);   % ZF receiver                  
                    case 'MMSE'
                        temp = P'*P;
                        F = (temp+sigma_n2*eye(size(temp)))^-1*P';  % MMSE receiver
%                     case 'SSD'
%                         Jr = real(H_t*W);
%                         Ji = imag(H_t*W);
%                         J = [Jr(1,1),-Ji(1,1),Jr(1,2),-Ji(1,2);Ji(1,1),Jr(1,1),Ji(1,2),Jr(1,2);Jr(2,1),-Ji(2,1),Jr(2,2),-Ji(2,2);Ji(2,1),Jr(2,1),Ji(2,2),Jr(2,2)]; % Lattice generator
%                         % calculate error covariance matrix, assuming AWGN
%                         E(:,:,i) = (J'*J)^-1;
%                         F = eye(size(P,1));
                    otherwise
                        temp = P'*P;
                        F = (temp+sigma_n2*eye(size(temp)))^-1*P';  % MMSE receiver
                end
                K = F*P;
                SNR(i+1,rr,1:rr) = abs(diag(K)).^2./(sum(abs(K-diag(diag(K))).^2,2)+(sigma_n2+MSE_mean(1:rr)).*sum(abs(F).^2,2));
%                 I(i+1,rr) = sum(log2(1+SNR(i+1,rr,:)));  % rate of one resource block for different precoders and ranks
%                 for r_ = 1:rr
%                     I(i+1,rr) = I(i+1,rr) + LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,rr)));
%                 end
                if rr == 4
                        I(i+1,rr) = LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,1:2)))+LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,3:4))); % LTE just supports 2 codewords which are mapped like this to the four layers
                elseif rr == 3
                        I(i+1,rr) = LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,1)))+LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,2:3)));
                elseif rr == 2
                        I(i+1,rr) = LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,1)))+LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,2)));
                else
                        I(i+1,rr) = LTE_feedback_getBICM(LTE_params,squeeze(SNR(i+1,rr,1)));
                end
            end
        end
        I_g(:,:,RB_i,slot_i) = I_g(:,:,RB_i,slot_i) + I;
        SNR = 10*log10(SNR);
        SNR(isnan(SNR))= -inf;
        SNR_g(:,1:max(rank_loop),RB_i,slot_i,1:max(rank_loop)) = SNR;
        if ~LTE_params.feedback.channel_averaging
             I_RB = I_RB+I;
             if ~mod(RB_i,gran)
                [~,C1] = max(I,[],1);
%                 if slot_max == 1
%                     PMI_temp(:,RB_i/gran,:) = repmat(C1',[1,1,2]);
%                 else
                    PMI_temp(:,RB_i/gran,slot_i) = C1;
%                 end
                I_RB = 0;
             end
        else
            if UE.PMI_fb_gran == 1 
                [~,C1] = max(I,[],1);
%                 if slot_max == 1
%                     PMI_temp(:,RB_i,:) = repmat(C1',[1,1,2]);
%                 else
                    PMI_temp(:,RB_i,slot_i) = C1;
%                 end
            end
        end
%         if UE.PMI_fb_gran == 1 
%             [~,C1] = max(I,[],1);
%             PMI_temp(:,RB_i,slot_i) = C1;
%         end
    end
end

I_ges = sum(sum(I_g,3),4);
[~,I1] = max(max(I_ges,[],1));
rank_i = I1;    % choose rank indicator to maximize mutual information
if UE.PMI_fb_gran ~= 1
    if UE.PMI_fb
        [~,I2] = max(I_ges(:,rank_i));
        PMI = I2*ones(LTE_params.Nrb,2);
    else
        PMI = LTE_params.scheduler.PMI;
    end
    if LTE_params.UE_config.CQI_fb % wheter CQI feedback is used
%         for i2 = 1:min(2,rank_i)   % iterate over the number of streams
         for i2 = 1:rank_i   % iterate over the number of layers
            if UE.CQI_fb_gran ~= 1  % single CQI value for whole bandwidth
%                 if rank_i == 4
%                     AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,:,:,(i2-1)*2+1:i2*2));
%                 elseif rank_i == 3 && i2 == 2
%                     AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,:,:,i2:rank_i));
%                 else
%                     AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,:,:,i2));
%                 end
                AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,:,:,i2));
                CQIs = (0:15);
%                 SINReff = UE.SINR_averager.average(10.^(AWGN_SNR(:)/10),CQIs,[LTE_params.CQI_params(CQIs+1).modulation_order]);
                SINReff = UE.SINR_averager.average(10.^(AWGN_SNR(:)/10),CQIs,[LTE_params.CQI_params(20).modulation_order,LTE_params.CQI_params(CQIs(2:end)).modulation_order]);
                CQI_temp = LTE_common_CQI_mapping_table(LTE_params.CQI_mapping,SINReff,CQIs+1);
                CQI(:,:,i2) = CQI_temp*ones(LTE_params.Nrb,2);
            else  % single CQI value for every resource block
                for RB_ii = 1:LTE_params.Nrb
                    if LTE_params.feedback.channel_averaging
                        rb_ii = RB_ii;
                    else
                        rb_ii = (RB_ii-1)*gran+1:RB_ii*gran;
                    end
                    for slot_ii = 1:2
%                         if rank_i == 4
%                             AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,rb_ii,slot_ii,(i2-1)*2+1:min(i2*2,rank_i)));
%                         elseif rank_i == 3 && i2 == 2
%                             AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,rb_ii,slot_ii,i2:rank_i));
%                         else
%                             AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,rb_ii,slot_ii,i2));
%                         end
                        AWGN_SNR = squeeze(SNR_g(PMI(1),rank_i,rb_ii,slot_ii,i2));
                        CQIs = (0:15);
                        SINReff = UE.SINR_averager.average(10.^(AWGN_SNR(:)/10),CQIs,[LTE_params.CQI_params(20).modulation_order,LTE_params.CQI_params(CQIs(2:end)).modulation_order]);
                        CQI_temp = LTE_common_CQI_mapping_table(LTE_params.CQI_mapping,SINReff,CQIs+1);
                        CQI(RB_ii,slot_ii,i2) = CQI_temp;
                    end
                end
            end
        end
    else
        CQI = [];
    end
else
%     for i2 = 1:min(2,rank_i)   % iterate over the number of streams
     for i2 = 1:rank_i   % iterate over the number of layers
        if UE.PMI_fb
            PMI = squeeze(PMI_temp(rank_i,:,:));
        else
            PMI = LTE_params.scheduler.PMI;
        end    
        if LTE_params.UE_config.CQI_fb % wheter CQI feedback is used
        AWGN_SNR = [];
            if UE.CQI_fb_gran ~= 1
                for RB_ii = 1:LTE_params.Nrb
                    if LTE_params.feedback.channel_averaging
                        rb_ii = RB_ii;
                    else
                        rb_ii = (RB_ii-1)*gran+1:RB_ii*gran;
                    end
                    for slot_ii = 1:2
%                         if rank_i == 4
%                             AWGN_SNR = [AWGN_SNR,squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,(i2-1)*2+1:i2*2))];
%                         elseif rank_i == 3 && i2 == 2
%                             AWGN_SNR = [AWGN_SNR,squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_iii,slot_ii,i2:rank_i))];
%                         else
%                             AWGN_SNR = [AWGN_SNR,squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,i2))];
%                         end
                          AWGN_SNR = [AWGN_SNR,squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,i2))];
                    end
                end
                CQIs = (0:15);
                SINReff = UE.SINR_averager.average(10.^(AWGN_SNR(:)/10),CQIs,[LTE_params.CQI_params(20).modulation_order,LTE_params.CQI_params(CQIs(2:end)).modulation_order]);
                CQI_temp = LTE_common_CQI_mapping_table(LTE_params.CQI_mapping,SINReff,CQIs+1);
                CQI(:,:,i2) = CQI_temp*ones(LTE_params.Nrb,2);
            else
                for RB_ii = 1:LTE_params.Nrb
                    if LTE_params.feedback.channel_averaging
                        rb_ii = RB_ii;
                    else
                        rb_ii = (RB_ii-1)*gran+1:RB_ii*gran;
                    end
                    for slot_ii = 1:2
%                         if rank_i == 4
%                             AWGN_SNR = squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,(i2-1)*2+1:i2*2));
%                         elseif rank_i == 3 && i2 == 2
%                             AWGN_SNR = squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,i2:rank_i));
%                         else
%                             AWGN_SNR = squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,i2));
%                         end
                        AWGN_SNR = squeeze(SNR_g(PMI(RB_ii,slot_ii),rank_i,rb_ii,slot_ii,i2));
                        CQIs = (0:15);
                        SINReff = UE.SINR_averager.average(10.^(AWGN_SNR(:)/10),CQIs,[LTE_params.CQI_params(20).modulation_order,LTE_params.CQI_params(CQIs(2:end)).modulation_order]);
                        CQI_temp = LTE_common_CQI_mapping_table(LTE_params.CQI_mapping,SINReff,CQIs+1);
                        CQI(RB_ii,slot_ii,i2) = CQI_temp;
                    end
                end
            end
        else
            CQI = [];
        end
    end
end
if ~UE.PMI_fb
    PMI = [];
end
% PMI
% CQI
% rank_i
% error('jetzt')



