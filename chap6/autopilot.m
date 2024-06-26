function y = autopilot(uu, AP)
%
% autopilot for mavsim
% 
% Modification History:
%   2/11/2010 - RWB
%   5/14/2010 - RWB
%   11/14/2014 - RWB
%   2/16/2019 - RWB
%   

    % process inputs
    NN = 0;
    pn       = uu(1+NN);  % inertial North position
    pe       = uu(2+NN);  % inertial East position
    h        = uu(3+NN);  % altitude
    Va       = uu(4+NN);  % airspeed
    alpha    = uu(5+NN);  % angle of attack
    beta     = uu(6+NN);  % side slip angle
    phi      = uu(7+NN);  % roll angle
    theta    = uu(8+NN);  % pitch angle
    chi      = uu(9+NN);  % course angle
    p        = uu(10+NN); % body frame roll rate
    q        = uu(11+NN); % body frame pitch rate
    r        = uu(12+NN); % body frame yaw rate
    Vg       = uu(13+NN); % ground speed
    wn       = uu(14+NN); % wind North
    we       = uu(15+NN); % wind East
    psi      = uu(16+NN); % heading
    bx       = uu(17+NN); % x-gyro bias
    by       = uu(18+NN); % y-gyro bias
    bz       = uu(19+NN); % z-gyro bias
    NN = NN+19;
    Va_c     = uu(1+NN);  % commanded airspeed (m/s)
    h_c      = uu(2+NN);  % commanded altitude (m)
    chi_c    = uu(3+NN);  % commanded course (rad)
    
%     % If phi_c_ff is specified in Simulink model, then do the following
%     phi_c_ff = uu(4+NN);  % feedforward roll command (rad)
%     NN = NN+4;
    
    % If no phi_c_ff is included in inputs in Simulink model, then do this
    NN = NN+3;
    phi_c_ff = 0;
    
    t        = uu(1+NN);   % time
    
    %----------------------------------------------------------
    % lateral autopilot
    % chi_ref = wrap(chi_c, chi);
    if t==0
        phi_c   = course_with_roll(chi_c, chi, 1, AP);
        delta_r = 0;
    else
        phi_c   = course_with_roll(chi_c, chi, 0, AP);
        delta_r = 0;
    end
    delta_a = roll_with_aileron(phi_c, phi, p, AP);
  
    
    %----------------------------------------------------------
    % longitudinal autopilot
    
    h_ref = sat(h_c, h+AP.altitude_zone, h-AP.altitude_zone);
    if t==0
        delta_t = airspeed_with_throttle(Va_c, Va, 1, AP);
        theta_c = altitude_with_pitch(h_ref, h, 1, AP);
    else
        delta_t = airspeed_with_throttle(Va_c, Va, 0, AP);
        theta_c = altitude_with_pitch(h_ref, h, 0, AP);
    end
    delta_e = pitch_with_elevator(theta_c, theta, q, AP);
    
    % limit range of throttle setting to [0,1]
    delta_t = sat(delta_t, 1, 0);
 
    
    %----------------------------------------------------------
    % create outputs
    
    % control outputs
    delta = [delta_e; delta_a; delta_r; delta_t];
    % commanded (desired) states
    x_command = [...
        0;...                    % pn
        0;...                    % pe
        h_c;...                  % h
        Va_c;...                 % Va
        0;...                    % alpha
        0;...                    % beta
        phi_c;...                % phi
        theta_c;...              % theta
        chi_c;...                % chi
        0;...                    % p
        0;...                    % q
        0;...                    % r
        ];
            
    y = [delta; x_command];
 
    end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Autopilot functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% course_with_roll
%   - regulate heading using the roll command
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function phi_c_sat = course_with_roll(chi_c, chi, flag, AP)
    
    persistent error_integral;
    persistent error;

    if flag == 1
        
        error_integral = 0;
    end
    
    %add up the errors from the previous time

    error_integral = error_integral + AP.Ts*(chi_c - chi);
    error = chi_c - chi;

    phi_c = AP.course_kp*(error)+AP.course_ki*(error_integral);
    
    phi_c_sat = sat(phi_c , 40*pi/180 , -40*pi/180) ; 



end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% roll_with_aileron
%   - regulate roll using aileron
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function delta_a = roll_with_aileron(phi_c, phi, p, AP)

    persistent error_integral;

    if flag == 1
        error_integral = 0;
    end
    
    error_integral = error_integral + AP.Ts*(phi_c-phi);

    %MAKE INTEGRAL ERROR 0 IF WE WANT TO DO WITHOUT DISTURBANCE

    % delta a max is 40 degrees and error max is assumed 5 degrees thus kp
    % is 40/5 = 8

    delta_a = AP.roll_kp*(phi_c-phi) - AP.roll_kd*p + AP.roll_ki*(error_integral);
    delta_a = sat(delta_a, 40*pi/180, -40*pi/180);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% pitch_with_elevator
%   - regulate pitch using elevator
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function delta_e = pitch_with_elevator(theta_c, theta, q, AP)

    delta_e = AP.pitch_kp*(theta_c - theta) - AP.pitch_kd*q;
    delta_e = sat(delta_e, 40*pi/180, -40*pi/180);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% airspeed_with_throttle
%   - regulate airspeed using throttle
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function delta_t_sat = airspeed_with_throttle(Va_c, Va, flag, AP)
    
    persistent error_integral;

    if flag == 1
        error_integral = 0;
    end
    
    error_integral = error_integral + AP.Ts*(Va_c - Va);

    delta_t = AP.airspeed_throttle_kp*(Va_c - Va) + AP.airspeed_throttle_ki*i_error;
    delta_t_sat = sat(delta_t, 1, 0);

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% altitude_with_pitch
%   - regulate altitude using pitch angle
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function theta_c_sat = altitude_with_pitch(h_c, h, flag, AP)

    persistent error_integral;

    if flag == 1
        error_integral = 0;

    end
    
    error_integral = error_integral + AP.Ts*(h_c - h);

    theta_c = AP.altitude_kp*(h_c - h) + AP.altitude_ki*i_error;
    theta_c_sat = sat(theta_c, 40*pi/180, -40*pi/180);


end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% coordinated_turn_hold
%   - sideslip with rudder
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% function theta_r = sideslip_with_rudder(v, flag, AP)

    % %assuming sideslip and yaw are similar
    % 
    % persistent error_integral;
    % persistent error;
    % 
    % if flag == 1
    %     error = 0;
    %     error_integral = 0;
    % end
    % 
    % %add up the errors from the previous time
    % %assuming time step as a random value of 0.01 (wouldnt matter
    % %since it gets multiplied with a constant anyways
    % error_integral = error_integral + 0.01*(chi_c - chi);
    % error = chi_c - chi;
    % 
    % theta_r = AP.sideslip_kp*(error)+AP.sideslip_ki*(error_integral);
    % 
    % theta_r = sat(theta_r , 40*pi/180 , -40*pi/180) ;

% end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% yaw_damper
%   - yaw rate with rudder
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% function delta_r = yaw_damper(r, flag, AP)
% end
  
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% sat
%   - saturation function
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function out = sat(in, up_limit, low_limit)

  if in < low_limit
      out = low_limit; 

  elseif in > up_limit
      out = up_limit;
  
  else
      out = in;
  end

end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% wrap
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% function chi_c = wrap(chi_c, chi)
% end

  
 