import { spawnSync } from 'node:child_process';

export function syncTokensToTeslaMateRuntime({
  accessToken,
  refreshToken,
  containerName = 'teslamate-stack-teslamate-1',
  dockerBin = 'docker',
  teslamateBin = '/opt/app/bin/teslamate'
}) {
  const access = String(accessToken || '').trim();
  const refresh = String(refreshToken || '').trim();
  if (!access || !refresh) {
    throw new Error('Both access token and refresh token are required for TeslaMate sync.');
  }

  const accessB64 = Buffer.from(access, 'utf8').toString('base64');
  const refreshB64 = Buffer.from(refresh, 'utf8').toString('base64');
  const rpc = [
    `a = "${accessB64}" |> Base.decode64!()`,
    `r = "${refreshB64}" |> Base.decode64!()`,
    'save = TeslaMate.Auth.save(%{token: a, refresh_token: r})',
    'sign = TeslaMate.Api.sign_in(TeslaMate.Auth.get_tokens())',
    'IO.inspect(save)',
    'IO.inspect(sign)'
  ].join('; ');

  const result = spawnSync(dockerBin, ['exec', containerName, teslamateBin, 'rpc', rpc], {
    encoding: 'utf8',
    stdio: 'pipe'
  });

  if (result.error) {
    throw new Error(`Failed to run docker exec: ${result.error.message}`);
  }
  if (result.status !== 0) {
    const stderr = String(result.stderr || '').trim();
    const stdout = String(result.stdout || '').trim();
    throw new Error(`TeslaMate token sync failed (exit ${result.status}): ${stderr || stdout || 'unknown error'}`);
  }

  return {
    stdout: String(result.stdout || '').trim(),
    stderr: String(result.stderr || '').trim()
  };
}
