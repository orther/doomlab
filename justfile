default:
  just --list

deploy machine ip='':
  #!/usr/bin/env sh
  if [ {{machine}} = "macos" ]; then
    darwin-rebuild switch --flake .
  elif [ -z "{{ip}}" ]; then
    sudo nixos-rebuild switch --fast --flake ".#{{machine}}"
  else
    nixos-rebuild switch --fast --flake ".#{{machine}}" --use-remote-sudo --target-host "orther@{{ip}}" --build-host "orther@{{ip}}"
  fi

up:
  nix flake update

lint:
  statix check .

gc:
  sudo nix profile wipe-history --profile /nix/var/nix/profiles/system --older-than 7d && sudo nix store gc

repair:
  sudo nix-store --verify --check-contents --repair

sopsedit:
  sops secrets/secrets.yaml

sopsrotate:
  for file in secrets/*; do sops --rotate --in-place "$file"; done
  
sopsupdate:
  for file in secrets/*; do sops updatekeys "$file"; done

build-iso:
  nix build .#nixosConfigurations.iso1chng.config.system.build.isoImage

fix-sop-keystxt:
  mkdir -p ~/.config/sops/age
  sudo nix-shell --extra-experimental-features flakes -p ssh-to-age --run 'ssh-to-age -private-key -i /nix/secret/initrd/ssh_host_ed25519_key -o /home/orther/.config/sops/age/keys.txt'
  sudo chown -R orther:users ~/.config/sops/age
