# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  llamaProxyEnv = pkgs.python313Packages.python.withPackages (ps: [
    ps.fastapi
    ps.uvicorn
    ps.httpx
  ]);

  llamaCoderServer = (pkgs.llama-cpp.override {
    cudaSupport = true;
  }).overrideAttrs (oldAttrs: {
    cmakeFlags = (oldAttrs.cmakeFlags or []) ++ [
      "-DGGML_CUDA=ON"
      "-DGGML_CUDA_F16=OFF"
      "-DCMAKE_CUDA_ARCHITECTURES=61"
    ];
  });
in {
  imports =[
    ./hardware-configuration.nix
  ];

  # BootLoader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Networking
  networking.hostName = "homeserver";
  networking.networkmanager.enable = true;


  # Time and Language
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_GB.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  console.keyMap = "de";



  # User
  users.users."homeserver" = {
    isNormalUser = true;
    description = "homeserver";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
    packages = with pkgs; [];
  };
  users.groups.homeserver = {};




  # Nvidia
  nixpkgs.config.allowUnfree = true; 
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    open = false;

    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    nvidiaSettings = true;

    powerManagement.enable = false;
    powerManagement.finegrained = false;
      
    modesetting.enable = true;
  };
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  environment.variables = {
    CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
    LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib";
  };


  # Packages
  environment.systemPackages = with pkgs; [
    docker vim
    wakeonlan 
    openssh tmux
    git git-lfs
    iputils
    (btop.override { cudaSupport = true; })
    cudaPackages.cudatoolkit cudaPackages.cudnn
    llamaCoderServer
    python3Packages.huggingface-hub 
  ];

  

  # Enable Docker
  virtualisation.docker.enable = true;

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;


  # Open ports in the firewall.
  networking.firewall.trustedInterfaces = ["docker0"];
  networking.firewall.allowPing = true;
  networking.firewall.allowedTCPPorts = [ 22 3000 3030 9090 8000 8080 25565 25566 25567 25568 25569 ];
  # networking.firewall.allowedUDPPorts = [ ... ];


  
  
  systemd.services.llama-proxy = {
    description = "Llama Inference Proxy Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    restartTriggers = [ config.environment.etc."llama-proxy/main.py".source ];

    path = [ pkgs.iputils pkgs.wakeonlan pkgs.openssh ];
      
    serviceConfig = {
      Type = "simple";
      ExecStart = "${llamaProxyEnv}/bin/python /etc/llama-proxy/main.py";
      Restart = "always";
      RestartSec = "5";
	
      User = "homeserver"; 
      Group = "homeserver";
		
      StandardOutput = "append:/home/homeserver/AI/llama-proxy/llama-proxy-logs.log";
      StandardError = "append:/home/homeserver/AI/llama-proxy/llama-proxy-logs.log";
    };
  };


  systemd.services.llama-code = {
    description = "llama.cpp Server for Coding Completion";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      Environment = "CUDA_VISIBLE_DEVICES=1";

      ExecStart = ''
        ${llamaCoderServer}/bin/llama-server \
        --model /home/homeserver/AI/llama-server/Qwen2.5-Coder-7B-Q4.gguf \
        --alias "Qwen2.5-Coder-7B" \

        --host 0.0.0.0 \
        --port 8080 \

        --n-gpu-layers 999 \
        --flash-attn \
        --parallel 4 \

        --ctx-size 8192 \
        --cache-reuse 256 \
        --ctk q4_0 \
        --ctv q4_0 \
        --ctx-checkpoints 4
      '';

      Restart = "always";
      RestartSec = "5";

      User = "homeserver";
      Group = "homeserver";

      StandardOutput = "append:/home/homeserver/AI/llama-server/llama-code-logs.log";
      StandardError = "append:/home/homeserver/AI/llama-server/llama-code-logs.log";
    };
  };

  systemd.services.llama-chat = {
    description = "llama.cpp Server for normal Chat model";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      Type = "simple";
      Environment = "CUDA_VISIBLE_DEVICES=0";

      ExecStart = ''
        ${llamaCoderServer}/bin/llama-server \
        --model /home/homeserver/AI/llama-server/Qwen3.5-9B-Q6.gguf \
        --alias "Qwen3.5-9B" \

        --host 0.0.0.0 \
        --port 8070 \

        --n-gpu-layers 999 \
        --parallel 4 \
        --flash-attn \

        --ctk q4_0 \
        --ctv q4_0 \
        --ctx-checkpoints 4
      '';

      Restart = "always";
      RestartSec = "5";

      User = "homeserver";
      Group = "homeserver";

      StandardOutput = "append:/home/homeserver/AI/llama-server/llama-chat-logs.log";
      StandardError = "append:/home/homeserver/AI/llama-server/llama-chat-logs.log";
    };
  };

  environment.etc."llama-proxy/main.py".source = ./llama-proxy.py;


  system.stateVersion = "26.05";

}
