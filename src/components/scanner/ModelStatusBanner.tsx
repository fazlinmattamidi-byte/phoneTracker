import React from 'react';
import { Cpu, AlertTriangle, Zap, RefreshCw, AlertOctagon, HelpCircle, CheckCircle2 } from 'lucide-react';
import { ANPRRuntimeState, AdmissionBenchmarkResult } from '@/lib/anpr/runtimeManager';
import type { EnvironmentModelStatus } from '@/lib/anpr/environmentIntelligence';

interface ModelStatusBannerProps {
  runtimeState: ANPRRuntimeState;
  detectorProvider?: 'WebGPU' | 'WASM' | 'NONE';
  ocrProvider?: 'WebGPU' | 'WASM' | 'NONE';
  environmentStatus?: EnvironmentModelStatus;
  benchmark?: AdmissionBenchmarkResult | null;
  errorMessage?: string | null;
  debugMode?: boolean;
  onRetry?: () => void;
  onManualSearch?: () => void;
}

export const ModelStatusBanner: React.FC<ModelStatusBannerProps> = ({
  runtimeState,
  detectorProvider = 'NONE',
  ocrProvider = 'NONE',
  environmentStatus = 'UNINITIALIZED',
  benchmark,
  errorMessage,
  debugMode = false,
  onRetry,
  onManualSearch,
}) => {
  const isReady = runtimeState === 'READY_WEBGPU' || runtimeState === 'READY_WASM';
  const isDegraded = runtimeState === 'DEGRADED_PERFORMANCE';
  const isUnavailable = runtimeState === 'DETECTOR_UNAVAILABLE' || runtimeState === 'OCR_UNAVAILABLE' || runtimeState === 'RUNTIME_ERROR';
  const detectorReady = (isReady || isDegraded) && detectorProvider !== 'NONE';
  const ocrReady = ocrProvider !== 'NONE';
  const environmentReady =
    environmentStatus === 'READY' ||
    environmentStatus === 'FALLBACK' ||
    environmentStatus === 'FAILED' ||
    environmentStatus === 'UNINITIALIZED';
  const scannerReady = detectorReady && ocrReady && environmentReady;
  const environmentLabel =
    environmentStatus === 'READY'
      ? 'Ready'
      : environmentStatus === 'LOADING'
      ? 'Loading'
      : environmentStatus === 'FAILED'
      ? 'Heuristic'
      : environmentStatus === 'FALLBACK'
      ? 'Heuristic'
      : 'Standby';
  const stages = [
    {
      label: 'Detector',
      value: detectorReady ? detectorProvider : runtimeState === 'DETECTOR_UNAVAILABLE' ? 'Error' : 'Loading',
      ready: detectorReady,
      error: runtimeState === 'DETECTOR_UNAVAILABLE' || runtimeState === 'RUNTIME_ERROR',
    },
    {
      label: 'OCR',
      value: ocrReady ? ocrProvider : runtimeState === 'OCR_UNAVAILABLE' ? 'Error' : 'Loading',
      ready: ocrReady,
      error: runtimeState === 'OCR_UNAVAILABLE',
    },
    {
      label: 'Tracker',
      value: 'Ready',
      ready: true,
      error: false,
    },
    {
      label: 'Environment AI',
      value: environmentLabel,
      ready: environmentReady,
      error: false,
    },
  ];

  // For normal users when ready and debugMode is false, keep UI 100% clean and transparent
  if (scannerReady && !isDegraded && !debugMode) {
    return null;
  }

  if (!debugMode) {
    const message = isUnavailable
      ? 'Scanner could not start. You can try again or use manual search.'
      : !detectorReady
      ? 'Loading Detector...'
      : !ocrReady
      ? 'Loading OCR...'
      : !environmentReady
      ? 'Loading Environment AI...'
      : isDegraded
      ? 'Scanner is running, but this device may be slow.'
      : 'Scanner is starting...';
    const Icon = isUnavailable ? AlertOctagon : isDegraded ? AlertTriangle : RefreshCw;

    return (
      <div className="flex flex-col gap-3 rounded-2xl border border-slate-800 bg-slate-950/95 p-3.5 text-xs shadow-xl">
        <div className="flex items-center gap-2">
          <Icon
            className={`h-4 w-4 shrink-0 ${
              isUnavailable ? 'text-rose-400' : isDegraded ? 'text-amber-400' : 'animate-spin text-cyan-300'
            }`}
          />
          <span className="font-bold text-slate-200">{message}</span>
        </div>
        <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
          {stages.map((stage) => (
            <div
              key={stage.label}
              className={`rounded-lg border px-2.5 py-2 ${
                stage.error
                  ? 'border-rose-900 bg-rose-950/30'
                  : stage.ready
                  ? 'border-emerald-900 bg-emerald-950/20'
                  : 'border-slate-800 bg-slate-900/75'
              }`}
            >
              <div className="flex items-center gap-1.5">
                {stage.ready ? (
                  <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-300" />
                ) : stage.error ? (
                  <AlertOctagon className="h-3.5 w-3.5 shrink-0 text-rose-300" />
                ) : (
                  <RefreshCw className="h-3.5 w-3.5 shrink-0 animate-spin text-cyan-300" />
                )}
                <span className="truncate text-[10px] font-black uppercase text-slate-400">{stage.label}</span>
              </div>
              <div className="mt-1 truncate font-mono text-[11px] font-bold text-slate-100">{stage.value}</div>
            </div>
          ))}
        </div>
        {(isUnavailable || isDegraded) && (
          <div className="flex flex-wrap items-center gap-2 pt-1">
            {onRetry && (
              <button
                onClick={onRetry}
                className="rounded-xl bg-cyan-600 px-3 py-2 text-xs font-bold text-white transition-colors hover:bg-cyan-500"
              >
                Try Again
              </button>
            )}
            {onManualSearch && (
              <button
                onClick={onManualSearch}
                className="rounded-xl border border-slate-700 bg-slate-800 px-3 py-2 text-xs font-bold text-slate-200 transition-colors hover:bg-slate-700"
              >
                Manual Search
              </button>
            )}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-2.5 p-3.5 bg-slate-950/95 border border-slate-800 rounded-2xl text-xs backdrop-blur-md shadow-2xl">
      <div className="flex items-center justify-between gap-2">
        {/* DETECTOR STATUS */}
        <div className="flex items-center gap-2">
          {detectorReady && ocrReady ? (
            <>
              <Cpu className="w-4 h-4 text-emerald-400 animate-pulse shrink-0" />
              <span className="font-bold text-emerald-400">AI Scanner Ready</span>
              <span className="px-2 py-0.5 bg-emerald-950/80 border border-emerald-800 rounded text-[9px] font-mono text-emerald-300 font-bold">
                {detectorProvider}/{ocrProvider}
              </span>
            </>
          ) : isDegraded ? (
            <>
              <AlertTriangle className="w-4 h-4 text-amber-400 shrink-0" />
              <span className="font-bold text-amber-400">Slow Scanning Speed</span>
            </>
          ) : isUnavailable ? (
            <>
              <AlertOctagon className="w-4 h-4 text-rose-500 shrink-0" />
              <span className="font-bold text-rose-400">
                {runtimeState === 'OCR_UNAVAILABLE' ? 'OCR Engine Loading Issue' : 'Detector Loading Issue'}
              </span>
            </>
          ) : (
            <>
              <RefreshCw className="w-4 h-4 text-[#00d8f6] animate-spin shrink-0" />
              <span className="font-bold text-[#00d8f6]">
                {!detectorReady
                  ? 'Loading Detector...'
                  : !ocrReady
                  ? 'Loading OCR...'
                  : !environmentReady
                  ? 'Loading Environment AI...'
                  : 'Initializing AI Scanner...'}
              </span>
            </>
          )}
        </div>

        {/* OCR ENGINE STATUS (Debug mode only) */}
        {scannerReady && debugMode && (
          <div className="flex items-center gap-2">
            <Zap className="w-4 h-4 text-[#00d8f6] shrink-0" />
            <span className="font-bold text-[#00d8f6]">PP-OCR {ocrProvider}</span>
          </div>
        )}
      </div>

      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        {stages.map((stage) => (
          <div
            key={stage.label}
            className={`rounded-lg border px-2.5 py-2 ${
              stage.error
                ? 'border-rose-900 bg-rose-950/30'
                : stage.ready
                ? 'border-emerald-900 bg-emerald-950/20'
                : 'border-slate-800 bg-slate-900/75'
            }`}
          >
            <div className="flex items-center gap-1.5">
              {stage.ready ? (
                <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-300" />
              ) : stage.error ? (
                <AlertOctagon className="h-3.5 w-3.5 shrink-0 text-rose-300" />
              ) : (
                <RefreshCw className="h-3.5 w-3.5 shrink-0 animate-spin text-cyan-300" />
              )}
              <span className="truncate text-[10px] font-black uppercase text-slate-400">{stage.label}</span>
            </div>
            <div className="mt-1 truncate font-mono text-[11px] font-bold text-slate-100">{stage.value}</div>
          </div>
        ))}
      </div>

      {/* BENCHMARK DIAGNOSTICS CHIP (Debug mode only) */}
      {benchmark && scannerReady && debugMode && (
        <div className="flex items-center justify-between text-[10px] font-mono text-slate-400 border-t border-slate-900 pt-1.5 px-1">
          <span>Det: {benchmark.detectorP95Ms}ms</span>
          <span>OCR: {benchmark.ocrP95Ms}ms</span>
          <span>{benchmark.estimatedFps} FPS</span>
        </div>
      )}

      {/* FRIENDLY ERROR & RETRY ACTION FOR END USERS */}
      {(isUnavailable || isDegraded) && (
        <div className="flex flex-col gap-2 pt-2 border-t border-slate-800/80">
          <p className="text-[11px] text-slate-300 leading-relaxed">
            {isUnavailable 
              ? 'Unable to start automatic AI scanning. You can retry initialization or use manual plate search.' 
              : 'Device scanning speed is reduced. Manual plate search is available.'}
          </p>
          {errorMessage && (
            <p className="text-[10px] text-rose-300/80 font-mono break-all leading-tight bg-rose-950/30 p-2 rounded-xl border border-rose-900/20">
              {errorMessage}
            </p>
          )}
          <div className="flex items-center gap-2 pt-1">
            {onRetry && (
              <button
                onClick={onRetry}
                className="flex-1 px-3 py-2 bg-[#00d8f6] hover:bg-[#22e0fb] text-slate-950 font-bold rounded-xl text-xs transition-colors flex items-center justify-center gap-1.5 shadow-lg shadow-[#00d8f6]/20"
              >
                <RefreshCw className="w-3.5 h-3.5" />
                Retry Scanner
              </button>
            )}
            {onManualSearch && (
              <button
                onClick={onManualSearch}
                className="flex-1 px-3 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 font-bold rounded-xl text-xs transition-colors flex items-center justify-center gap-1.5 border border-slate-700"
              >
                <HelpCircle className="w-3.5 h-3.5" />
                Manual Search
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
