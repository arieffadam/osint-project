# OSINT Project

Public-source username and profile correlation toolkit.

## Current version

`osint-username-v8.2.sh`

## Usage

Username:

    ./scripts/osint-username-v8.2.sh --username exampleuser

Username + public name:

    ./scripts/osint-username-v8.2.sh --username exampleuser --name "Example Name"

## Collectors

- Sherlock
- Maigret
- SocialScan
- InstagramOSINT
- WhatsMyName dataset detection
- theHarvester for eligible external domains

## Evidence model

Results are candidate public correlations, not proof that multiple accounts belong to the same person.

Username matches alone are insufficient for identity attribution. Stronger evidence may include public account cross-links, matching self-declared names or locations, distinctive public profile images, or the same linked website.

## Privacy and scope

This project is intended for lawful public-source research.

It does not attempt to obtain private credentials, login/source IP addresses, private home addresses, hidden contact information, or bypass authentication/access controls.

## Reports

Investigation reports are intentionally excluded from Git.
