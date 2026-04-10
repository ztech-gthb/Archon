import { describe, test, expect, beforeEach, afterEach } from 'bun:test';
import {
  buildRoutingRulesWithProject,
  buildOrchestratorPrompt,
  buildProjectScopedPrompt,
  formatWorkflowContextSection,
} from './prompt-builder';
import type { Codebase } from '../types';

describe('buildRoutingRulesWithProject', () => {
  test('routing rules include --prompt in invocation format', () => {
    const rules = buildRoutingRulesWithProject();

    expect(rules).toContain('--prompt');
    expect(rules).toContain('self-contained task description');
  });

  test('routing rules include --prompt with project-scoped prompt', () => {
    const rules = buildRoutingRulesWithProject('my-project');

    expect(rules).toContain('--prompt');
    expect(rules).toContain('my-project');
  });

  test('invocation format line includes exact --prompt flag syntax', () => {
    const rules = buildRoutingRulesWithProject();

    // The format template must include --prompt as part of the command, not just in prose
    expect(rules).toContain(
      '/invoke-workflow {workflow-name} --project {project-name} --prompt "{task description}"'
    );
  });

  test('rules state prompt must be self-contained with no conversation knowledge', () => {
    const rules = buildRoutingRulesWithProject();

    expect(rules).toContain('NO knowledge of the conversation history');
  });
});

describe('Docker path resolution in prompts', () => {
  let originalEnv: string | undefined;

  beforeEach(() => {
    originalEnv = process.env.ARCHON_DOCKER;
  });

  afterEach(() => {
    if (originalEnv === undefined) {
      delete process.env.ARCHON_DOCKER;
    } else {
      process.env.ARCHON_DOCKER = originalEnv;
    }
  });

  test('buildRoutingRulesWithProject uses /.archon/workspaces in Docker', () => {
    process.env.ARCHON_DOCKER = 'true';
    const rules = buildRoutingRulesWithProject();
    expect(rules).toContain('/.archon/workspaces');
    expect(rules).not.toContain('~/.archon');
  });

  test('buildRoutingRulesWithProject never uses literal ~ in Docker', () => {
    process.env.ARCHON_DOCKER = 'true';
    const rules = buildRoutingRulesWithProject('my-project');
    expect(rules).not.toContain('~/.archon');
  });

  test('buildOrchestratorPrompt uses /.archon/workspaces in Docker', () => {
    process.env.ARCHON_DOCKER = 'true';
    const prompt = buildOrchestratorPrompt([], []);
    expect(prompt).toContain('/.archon/workspaces');
    expect(prompt).not.toContain('~/.archon');
  });

  test('buildProjectScopedPrompt uses /.archon/workspaces in Docker', () => {
    process.env.ARCHON_DOCKER = 'true';
    const codebase: Codebase = {
      id: 'test-id',
      name: 'test/repo',
      repository_url: 'https://github.com/test/repo',
      default_cwd: '/.archon/workspaces/test/repo/source',
      ai_assistant_type: 'claude',
      commands: {},
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    const prompt = buildProjectScopedPrompt(codebase, [codebase], []);
    expect(prompt).toContain('/.archon/workspaces');
    expect(prompt).not.toContain('~/.archon');
  });
});

describe('formatWorkflowContextSection', () => {
  test('returns empty string for empty results array', () => {
    expect(formatWorkflowContextSection([])).toBe('');
  });

  test('includes section header for non-empty results', () => {
    const result = formatWorkflowContextSection([
      { workflowName: 'plan', runId: 'run-1', summary: 'Created implementation plan.' },
    ]);
    expect(result).toContain('## Recent Workflow Results');
    expect(result).toContain('Use this context to answer follow-up questions');
  });

  test('formats each result with workflowName and runId', () => {
    const result = formatWorkflowContextSection([
      { workflowName: 'implement', runId: 'abc-123', summary: 'Added auth module.' },
    ]);
    expect(result).toContain('**implement** (run: abc-123)');
    expect(result).toContain('Added auth module.');
  });

  test('formats multiple results sequentially', () => {
    const results = [
      { workflowName: 'plan', runId: 'run-1', summary: 'Plan done.' },
      { workflowName: 'implement', runId: 'run-2', summary: 'Implement done.' },
    ];
    const result = formatWorkflowContextSection(results);
    expect(result).toContain('**plan**');
    expect(result).toContain('**implement**');
  });

  test('output does not end with trailing whitespace', () => {
    const result = formatWorkflowContextSection([
      { workflowName: 'assist', runId: 'r-1', summary: 'Done.' },
    ]);
    expect(result).toBe(result.trimEnd());
  });
});
